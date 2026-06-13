require "test_helper"

class Connectors::PlivoProviderTest < ActiveSupport::TestCase
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
                         config: { "auth_id" => "MAXXXXXXXXXXXXXXXXXX", "from" => "+15005550006" }.merge(config))
    conn.credentials_hash = { "auth_token" => "tok-secret" }.merge(creds)
    Connectors::PlivoProvider.new(conn)
  end

  SENT_BODY = '{"message":"message(s) queued","message_uuid":["uuid-999"],"api_id":"api-1"}'.freeze

  # --- descriptor / decision-class ---

  test "descriptor declares the Plivo SMS connector as an effector-only comms provider" do
    d = Connectors::PlivoProvider.descriptor
    assert_equal "plivo", d.key
    assert_equal "Plivo (SMS)", d.name
    assert_equal "Communications", d.category
    assert_not d.syncs?
    assert_equal %w[auth_token], d.secret_fields
    assert_equal %w[auth_id from base_url], d.config_fields
  end

  test "send_sms is a :confirm action (a human confirms before a citizen send goes out)" do
    action = Connectors::PlivoProvider.action("send_sms")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  test "effector-only provider inherits an empty fetch" do
    assert_equal [], provider.fetch
  end

  # --- send_sms (network stubbed) ---

  test "send_sms posts a JSON message and returns the parsed observation" do
    with_http(202, SENT_BODY) do |reqs|
      obs = provider.invoke("send_sms", { "to" => "+15558675309", "text" => "Your case DKT-1 was updated" })
      assert obs["ok"]
      assert_equal [ "uuid-999" ], obs["message"]["message_uuid"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/v1/Account/MAXXXXXXXXXXXXXXXXXX/Message/", req.path
      assert_equal "application/json", req["Content-Type"]

      payload = JSON.parse(req.body)
      assert_equal "+15005550006", payload["src"]
      assert_equal "+15558675309", payload["dst"]
      assert_equal "Your case DKT-1 was updated", payload["text"]
    end
  end

  test "send_sms uses HTTP Basic auth with auth_id and auth_token" do
    with_http(202, SENT_BODY) do |reqs|
      provider.invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      auth = reqs.last.last["Authorization"]
      assert_equal "Basic " + [ "MAXXXXXXXXXXXXXXXXXX:tok-secret" ].pack("m0"), auth
    end
  end

  test "send_sms honours a configured base_url override without erroring" do
    with_http(202, SENT_BODY) do |reqs|
      obs = provider(config: { "base_url" => "https://api.plivo.test" })
            .invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      assert obs["ok"]
      assert_equal "/v1/Account/MAXXXXXXXXXXXXXXXXXX/Message/", reqs.last.last.path
    end
  end

  test "send_sms accepts symbol-keyed args" do
    with_http(202, SENT_BODY) do |reqs|
      obs = provider.invoke("send_sms", { to: "+15558675309", text: "hi" })
      assert obs["ok"]
      payload = JSON.parse(reqs.last.last.body)
      assert_equal "+15558675309", payload["dst"]
    end
  end

  # --- failure modes ---

  test "send_sms raises on a non-2xx response" do
    with_http(401, '{"error":"the credentials supplied are invalid"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      end
    end
  end

  test "send_sms requires a recipient" do
    with_http(202, SENT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("send_sms", { "text" => "hi" }) }
    end
  end

  test "send_sms requires a body" do
    with_http(202, SENT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("send_sms", { "to" => "+15558675309" }) }
    end
  end

  test "send_sms requires the auth_token secret" do
    assert_raises(Connectors::Error) do
      provider(creds: { "auth_token" => "" }).invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
    end
  end

  test "send_sms requires the auth_id config" do
    assert_raises(Connectors::Error) do
      provider(config: { "auth_id" => "" }).invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
