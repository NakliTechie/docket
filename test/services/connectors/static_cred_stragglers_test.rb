require "test_helper"

# The static-credential stragglers — Calendly, SurveyMonkey, Qualtrics, Metabase
# — on Connectors::HttpProvider. Read-mostly effectors; auth schemes vary
# (Bearer vs X-API-TOKEN vs x-api-key). Network is stubbed at Net::HTTP.
class Connectors::StaticCredStragglersTest < ActiveSupport::TestCase
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

  def conn(provider, config: {}, creds: {})
    c = Connector.new(name: provider, provider: provider, config: config)
    c.credentials_hash = creds
    c
  end

  # --- Calendly ---

  test "calendly list_events is autonomous read; create link is confirm" do
    assert_equal :autonomous, Connectors::CalendlyProvider.action("list_events").effective_decision_class
    assert_equal :confirm, Connectors::CalendlyProvider.action("create_scheduling_link").effective_decision_class
  end

  test "calendly list_events GETs scheduled_events for the configured user with a Bearer token" do
    c = conn("calendly", config: { "user_uri" => "https://api.calendly.com/users/U1" }, creds: { "access_token" => "cal-tok" })
    with_http(200, %({"collection":[{"uri":"e1","name":"Demo"}]})) do |reqs|
      obs = c.provider_instance.invoke("list_events", { "count" => 5, "status" => "active" })
      assert_equal "e1", obs["events"].first["uri"]
      req = reqs.last.last
      assert_includes req.path, "/scheduled_events?"
      assert_includes req.path, CGI.escape("https://api.calendly.com/users/U1")
      assert_includes req.path, "count=5"
      assert_equal "Bearer cal-tok", req["Authorization"]
    end
  end

  test "calendly create_scheduling_link posts a single-use link and requires an event_type_uri" do
    c = conn("calendly", config: { "user_uri" => "https://api.calendly.com/users/U1" }, creds: { "access_token" => "cal-tok" })
    with_http(201, %({"resource":{"booking_url":"https://calendly.com/x"}})) do |reqs|
      obs = c.provider_instance.invoke("create_scheduling_link", { "event_type_uri" => "https://api.calendly.com/event_types/ET1" })
      assert obs["ok"]
      sent = JSON.parse(reqs.last.last.body)
      assert_equal 1, sent["max_event_count"]
      assert_equal "https://api.calendly.com/event_types/ET1", sent["owner"]
      assert_equal "EventType", sent["owner_type"]
    end
    assert_raises(Connectors::Error) { c.provider_instance.invoke("create_scheduling_link", {}) }
  end

  # --- SurveyMonkey ---

  test "surveymonkey lists surveys and pulls bulk responses (both reads)" do
    c = conn("surveymonkey", creds: { "access_token" => "sm-tok" })
    with_http(200, %({"data":[{"id":"123","title":"NPS"}]})) do |reqs|
      obs = c.provider_instance.invoke("list_surveys", { "per_page" => 200 })
      assert_equal "123", obs["surveys"].first["id"]
      assert_includes reqs.last.last.path, "per_page=100" # clamped
      assert_equal "Bearer sm-tok", reqs.last.last["Authorization"]
    end
    with_http(200, %({"data":[{"id":"r1"}]})) do |reqs|
      obs = c.provider_instance.invoke("get_responses", { "survey_id" => "123" })
      assert_equal "r1", obs["responses"].first["id"]
      assert_equal "/v3/surveys/123/responses/bulk?per_page=25", reqs.last.last.path
    end
    assert_raises(Connectors::Error) { c.provider_instance.invoke("get_responses", {}) }
  end

  # --- Qualtrics ---

  test "qualtrics uses the X-API-TOKEN header and the configured datacenter base" do
    c = conn("qualtrics", config: { "base_url" => "https://iad1.qualtrics.com" }, creds: { "api_token" => "qx-tok" })
    with_http(200, %({"result":{"elements":[{"id":"SV_1"}]}})) do |reqs|
      obs = c.provider_instance.invoke("list_surveys", {})
      assert_equal "SV_1", obs["surveys"].first["id"]
      req = reqs.last.last
      assert_equal "/API/v3/surveys", req.path
      assert_equal "qx-tok", req["X-Api-Token"] # Net::HTTP canonicalises header case
      assert_nil req["Authorization"]
    end
  end

  test "qualtrics get_survey requires a survey_id and a base_url" do
    no_base = conn("qualtrics", creds: { "api_token" => "t" })
    assert_raises(Connectors::Error) { no_base.provider_instance.invoke("get_survey", { "survey_id" => "SV_1" }) }
    has_base = conn("qualtrics", config: { "base_url" => "https://iad1.qualtrics.com" }, creds: { "api_token" => "t" })
    assert_raises(Connectors::Error) { has_base.provider_instance.invoke("get_survey", {}) }
  end

  # --- Metabase ---

  test "metabase runs a card via x-api-key against the self-hosted base" do
    c = conn("metabase", config: { "base_url" => "https://mb.acme.internal" }, creds: { "api_key" => "mb-key" })
    with_http(200, %([{"id":1,"total":42}])) do |reqs|
      obs = c.provider_instance.invoke("run_card", { "card_id" => 7 })
      assert_equal 42, obs["rows"].first["total"]
      req = reqs.last.last
      assert_equal "/api/card/7/query/json", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "mb-key", req["X-Api-Key"]
    end
    assert_raises(Connectors::Error) { c.provider_instance.invoke("run_card", {}) }
  end

  test "metabase run_card is an autonomous read" do
    assert_equal :autonomous, Connectors::MetabaseProvider.action("run_card").effective_decision_class
  end

  # --- catalogue ---

  test "the four stragglers are registered, static-credential, effector-only" do
    %w[calendly surveymonkey qualtrics metabase].each do |key|
      desc = Connectors::Registry.descriptor(key)
      assert_equal key, desc.key
      assert_not desc.syncs?
      assert_not Connectors::Registry.klass(key) < Connectors::OauthProvider
    end
  end
end
