require "test_helper"

class Connectors::SinchProviderTest < ActiveSupport::TestCase
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

  def provider(config: {}, creds: {})
    conn = Connector.new(provider: "http_json", name: "t",
                         config: { "service_plan_id" => "sp-abc", "from" => "+15005550006" }.merge(config))
    conn.credentials_hash = { "api_token" => "tok-secret" }.merge(creds)
    Connectors::SinchProvider.new(conn)
  end

  SENT_BODY = '{"id":"BATCH-1","to":["+15558675309"],"from":"+15005550006","body":"hi"}'.freeze

  # --- descriptor / decision-class ---

  test "descriptor declares the Sinch SMS connector as an effector-only comms provider" do
    d = Connectors::SinchProvider.descriptor
    assert_equal "sinch", d.key
    assert_equal "Sinch (SMS)", d.name
    assert_equal "Communications", d.category
    assert_not d.syncs?
    assert_equal %w[api_token], d.secret_fields
    assert_equal %w[service_plan_id from base_url], d.config_fields
  end

  test "send_sms is a :confirm action (a human confirms before a citizen send goes out)" do
    action = Connectors::SinchProvider.action("send_sms")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  test "effector-only provider inherits an empty fetch" do
    assert_equal [], provider.fetch
  end

  # --- send_sms (network stubbed) ---

  test "send_sms posts a JSON batch with an array recipient and returns the parsed observation" do
    with_http(201, SENT_BODY) do |reqs|
      obs = provider.invoke("send_sms", { "to" => "+15558675309", "text" => "Your case DKT-1 was updated" })
      assert obs["ok"]
      assert_equal "+15558675309", obs["to"]
      assert_equal "BATCH-1", obs["message"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/xms/v1/sp-abc/batches", req.path
      assert_equal "application/json", req["Content-Type"]

      body = JSON.parse(req.body)
      assert_equal "+15005550006", body["from"]
      assert_equal [ "+15558675309" ], body["to"]
      assert_equal "Your case DKT-1 was updated", body["body"]
    end
  end

  test "send_sms uses Bearer auth with the api_token secret" do
    with_http(201, SENT_BODY) do |reqs|
      provider.invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      assert_equal "Bearer tok-secret", reqs.last.last["Authorization"]
    end
  end

  test "send_sms honours a configured base_url override" do
    with_http(201, SENT_BODY) do |reqs|
      obs = provider(config: { "base_url" => "https://sms.api.sinch.test" })
            .invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      assert obs["ok"]
      assert_equal "/xms/v1/sp-abc/batches", reqs.last.last.path
    end
  end

  test "send_sms accepts symbol-keyed args" do
    with_http(201, SENT_BODY) do |reqs|
      obs = provider.invoke("send_sms", { to: "+15558675309", text: "hi" })
      assert obs["ok"]
      body = JSON.parse(reqs.last.last.body)
      assert_equal [ "+15558675309" ], body["to"]
    end
  end

  # --- failure modes ---

  test "send_sms raises on a non-2xx response" do
    with_http(401, '{"code":40100,"text":"Unauthorized"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      end
    end
  end

  test "send_sms requires a recipient" do
    with_http(201, SENT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("send_sms", { "text" => "hi" }) }
    end
  end

  test "send_sms requires a body" do
    with_http(201, SENT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("send_sms", { "to" => "+15558675309" }) }
    end
  end

  test "send_sms requires the service_plan_id config" do
    with_http(201, SENT_BODY) do
      assert_raises(Connectors::Error) do
        provider(config: { "service_plan_id" => "" }).invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      end
    end
  end

  test "send_sms requires the api_token secret" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_token" => "" }).invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
