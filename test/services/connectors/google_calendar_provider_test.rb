require "test_helper"

# Exercises the OAuth2 foundation (Connectors::OauthProvider) through the
# Google Calendar reference provider: the authorize URL, the token exchange,
# transparent refresh-on-expiry, and a token-authenticated action.
class Connectors::GoogleCalendarProviderTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @r)
  end
  def with_http(code, body = "{}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def connector(config: {}, creds: {}, tokens: nil)
    c = Connector.create!(name: "GCal", provider: "google_calendar",
                          config: { "client_id" => "cid.apps", "calendar_id" => "primary" }.merge(config))
    c.credentials_hash = { "client_secret" => "topsecret" }.merge(creds)
    c.oauth_tokens = tokens if tokens
    c.save!
    c
  end

  def provider_for(c) = Connectors::GoogleCalendarProvider.new(c)

  # --- connector OAuth helpers ---

  test "the connector recognises google_calendar as an OAuth provider" do
    c = connector
    assert c.oauth?
    assert c.configured?         # client_secret present → ready to connect
    assert_not c.oauth_connected? # but no tokens yet
  end

  test "create_event is a confirm action" do
    assert_equal :confirm, Connectors::GoogleCalendarProvider.action("create_event").effective_decision_class
  end

  # --- authorize URL (no network) ---

  test "authorize_url carries client_id, redirect, scope, state and offline access" do
    url = Connectors::GoogleCalendarProvider.authorize_url(
      connector, redirect_uri: "https://docket.test/admin/connectors/oauth_callback", state: "STATE123"
    )
    assert url.start_with?("https://accounts.google.com/o/oauth2/v2/auth?")
    q = URI.decode_www_form(URI(url).query).to_h
    assert_equal "cid.apps", q["client_id"]
    assert_equal "https://docket.test/admin/connectors/oauth_callback", q["redirect_uri"]
    assert_equal "code", q["response_type"]
    assert_equal "https://www.googleapis.com/auth/calendar.events", q["scope"]
    assert_equal "STATE123", q["state"]
    assert_equal "offline", q["access_type"]
    assert_equal "consent", q["prompt"]
  end

  # --- token exchange + refresh ---

  test "exchange_code! posts to the token endpoint and stores the token bundle" do
    c = connector
    body = { access_token: "ya29.new", refresh_token: "1//refresh", expires_in: 3600, token_type: "Bearer" }.to_json
    with_http(200, body) do |reqs|
      provider_for(c).exchange_code!("auth-code-xyz", redirect_uri: "https://docket.test/cb")
      req = reqs.last.last
      assert_equal "/token", req.path
      form = URI.decode_www_form(req.body).to_h
      assert_equal "authorization_code", form["grant_type"]
      assert_equal "auth-code-xyz", form["code"]
      assert_equal "cid.apps", form["client_id"]
      assert_equal "topsecret", form["client_secret"]
      assert_equal "https://docket.test/cb", form["redirect_uri"]
    end
    c.reload
    assert_equal "ya29.new", c.oauth_tokens["access_token"]
    assert_equal "1//refresh", c.oauth_tokens["refresh_token"]
    assert c.oauth_connected?
    assert c.oauth_tokens["expires_at"].present?
  end

  test "access_token refreshes when expired and preserves a refresh token the response omits" do
    c = connector(tokens: { "access_token" => "old", "refresh_token" => "1//r", "expires_at" => 1.hour.ago.iso8601 })
    with_http(200, { access_token: "ya29.fresh", expires_in: 3600 }.to_json) do |reqs|
      assert_equal "ya29.fresh", provider_for(c).access_token
      form = URI.decode_www_form(reqs.last.last.body).to_h
      assert_equal "refresh_token", form["grant_type"]
      assert_equal "1//r", form["refresh_token"]
    end
    c.reload
    assert_equal "ya29.fresh", c.oauth_tokens["access_token"]
    assert_equal "1//r", c.oauth_tokens["refresh_token"] # preserved
  end

  test "access_token does not refresh while still valid" do
    c = connector(tokens: { "access_token" => "still-good", "expires_at" => 1.hour.from_now.iso8601 })
    # No HTTP stub installed — a refresh attempt would hit the network and fail.
    assert_equal "still-good", provider_for(c).access_token
  end

  test "access_token raises when the connector is not connected" do
    assert_raises(Connectors::Error) { provider_for(connector).access_token }
  end

  # --- the action ---

  test "create_event posts the event with a Bearer access token" do
    c = connector(tokens: { "access_token" => "ya29.live", "expires_at" => 1.hour.from_now.iso8601 })
    with_http(200, { id: "evt_1", status: "confirmed" }.to_json) do |reqs|
      obs = provider_for(c).invoke("create_event", {
        "summary" => "Demo call", "start_time" => "2026-07-01T10:00:00+05:30", "end_time" => "2026-07-01T10:30:00+05:30"
      })
      assert obs["ok"]
      assert_equal "evt_1", obs["event"]["id"]
      req = reqs.last.last
      assert_equal "/calendar/v3/calendars/primary/events", req.path
      assert_equal "Bearer ya29.live", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "Demo call", sent["summary"]
      assert_equal "2026-07-01T10:00:00+05:30", sent["start"]["dateTime"]
      assert_equal "2026-07-01T10:30:00+05:30", sent["end"]["dateTime"]
    end
  end

  test "create_event escapes a calendar id with an @ in the path" do
    c = connector(config: { "calendar_id" => "team@group.calendar.google.com" },
                  tokens: { "access_token" => "t", "expires_at" => 1.hour.from_now.iso8601 })
    with_http(200, "{}") do |reqs|
      provider_for(c).invoke("create_event", { "summary" => "x", "start_time" => "a", "end_time" => "b" })
      assert_equal "/calendar/v3/calendars/team%40group.calendar.google.com/events", reqs.last.last.path
    end
  end

  test "create_event requires summary, start and end" do
    c = connector(tokens: { "access_token" => "t", "expires_at" => 1.hour.from_now.iso8601 })
    p = provider_for(c)
    assert_raises(Connectors::Error) { p.invoke("create_event", { "start_time" => "a", "end_time" => "b" }) }
    assert_raises(Connectors::Error) { p.invoke("create_event", { "summary" => "s", "end_time" => "b" }) }
    assert_raises(Connectors::Error) { p.invoke("create_event", { "summary" => "s", "start_time" => "a" }) }
  end

  test "an unknown action raises" do
    c = connector(tokens: { "access_token" => "t", "expires_at" => 1.hour.from_now.iso8601 })
    assert_raises(Connectors::Error) { provider_for(c).invoke("nope", {}) }
  end
end
