require "test_helper"

# Microsoft 365 (Outlook mail + calendar) over Microsoft Graph, on the
# Connectors::OauthProvider seam. Token exchange/refresh is covered by the
# Google Calendar reference; here a live access token is set directly.
class Connectors::Microsoft365ProviderTest < ActiveSupport::TestCase
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

  def conn(tokens: { "access_token" => "tok", "expires_at" => 1.hour.from_now.iso8601 })
    c = Connector.create!(name: "M365", provider: "microsoft365", config: { "client_id" => "cid" })
    c.credentials_hash = { "client_secret" => "sec" }
    c.oauth_tokens = tokens if tokens
    c.save!
    c
  end

  def provider(c = conn) = Connectors::Microsoft365Provider.new(c)

  test "it is an OAuth, effector-only provider whose actions are confirm-class" do
    assert conn.oauth?
    assert_not Connectors::Microsoft365Provider.descriptor.syncs?
    assert_equal :confirm, Connectors::Microsoft365Provider.action("send_mail").effective_decision_class
    assert_equal :confirm, Connectors::Microsoft365Provider.action("create_event").effective_decision_class
  end

  test "the authorize scope requests offline_access so Graph returns a refresh token" do
    assert_includes Connectors::Microsoft365Provider.oauth_scope, "offline_access"
    assert_includes Connectors::Microsoft365Provider.oauth_scope, "Mail.Send"
  end

  test "send_mail posts a Graph message with split recipients and accepts a 202" do
    with_http(202, "") do |reqs|
      obs = provider.invoke("send_mail", { "to" => "a@b.com, c@d.com", "subject" => "Hi", "body" => "Hello" })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/v1.0/me/sendMail", req.path
      assert_equal "Bearer tok", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "Hi", sent["message"]["subject"]
      assert_equal "Text", sent["message"]["body"]["contentType"]
      addrs = sent["message"]["toRecipients"].map { |r| r["emailAddress"]["address"] }
      assert_equal %w[a@b.com c@d.com], addrs
      assert sent["saveToSentItems"]
    end
  end

  test "send_mail requires to, subject and body" do
    p = provider
    assert_raises(Connectors::Error) { p.invoke("send_mail", { "subject" => "s", "body" => "b" }) }
    assert_raises(Connectors::Error) { p.invoke("send_mail", { "to" => "a@b.com", "body" => "b" }) }
    assert_raises(Connectors::Error) { p.invoke("send_mail", { "to" => "a@b.com", "subject" => "s" }) }
  end

  test "create_event posts start/end with a time zone and optional notes" do
    with_http(201, %({"id":"evt_1","subject":"Demo"})) do |reqs|
      obs = provider.invoke("create_event",
        { "subject" => "Demo", "start_time" => "2026-07-01T10:00:00", "end_time" => "2026-07-01T10:30:00",
          "time_zone" => "Asia/Kolkata", "body" => "agenda" })
      assert_equal "evt_1", obs["event"]["id"]
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "/v1.0/me/events", reqs.last.last.path
      assert_equal "2026-07-01T10:00:00", sent["start"]["dateTime"]
      assert_equal "Asia/Kolkata", sent["start"]["timeZone"]
      assert_equal "agenda", sent["body"]["content"]
    end
  end

  test "create_event defaults the time zone to UTC and omits an empty body" do
    with_http(201, "{}") do |reqs|
      provider.invoke("create_event", { "subject" => "x", "start_time" => "a", "end_time" => "b" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "UTC", sent["start"]["timeZone"]
      assert_not sent.key?("body")
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
