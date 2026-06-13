require "test_helper"

class Connectors::KaleyraProviderTest < ActiveSupport::TestCase
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
                         config: { "sid" => "HXAB123", "sender" => "DOCKET" }.merge(config))
    conn.credentials_hash = { "api_key" => "kal-secret" }.merge(creds)
    Connectors::KaleyraProvider.new(conn)
  end

  SENT_BODY = '{"id":"msg-999","status":"queued","to":"+15558675309"}'.freeze

  # --- descriptor / decision-class ---

  test "descriptor declares the Kaleyra connector as an effector-only comms provider" do
    d = Connectors::KaleyraProvider.descriptor
    assert_equal "kaleyra", d.key
    assert_equal "Communications", d.category
    assert_not d.syncs?
    assert_equal %w[api_key], d.secret_fields
    assert_equal %w[sid sender base_url], d.config_fields
  end

  test "send_sms is a :confirm action (a human confirms before a citizen send goes out)" do
    action = Connectors::KaleyraProvider.action("send_sms")
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  test "effector-only provider inherits an empty fetch" do
    assert_equal [], provider.fetch
  end

  # --- send_sms (network stubbed) ---

  test "send_sms posts a form-encoded message with the sid in the path and returns the parsed observation" do
    with_http(202, SENT_BODY) do |reqs|
      obs = provider.invoke("send_sms", { "to" => "+15558675309", "text" => "Your case DKT-1 was updated" })
      assert obs["ok"]
      assert_equal "msg-999", obs["message"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/v1/HXAB123/messages", req.path
      assert_equal "application/x-www-form-urlencoded", req["Content-Type"]

      form = URI.decode_www_form(req.body).to_h
      assert_equal "+15558675309", form["to"]
      assert_equal "DOCKET", form["sender"]
      assert_equal "Your case DKT-1 was updated", form["body"]
      assert_equal "TXN", form["type"]
    end
  end

  test "send_sms authenticates with the api-key header" do
    with_http(202, SENT_BODY) do |reqs|
      provider.invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      assert_equal "kal-secret", reqs.last.last["api-key"]
    end
  end

  test "send_sms honours a configured base_url override without erroring" do
    with_http(202, SENT_BODY) do |reqs|
      obs = provider(config: { "base_url" => "https://api.kaleyra.test" })
            .invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
      assert obs["ok"]
      assert_equal "/v1/HXAB123/messages", reqs.last.last.path
    end
  end

  test "send_sms accepts symbol-keyed args" do
    with_http(202, SENT_BODY) do |reqs|
      obs = provider.invoke("send_sms", { to: "+15558675309", text: "hi" })
      assert obs["ok"]
      form = URI.decode_www_form(reqs.last.last.body).to_h
      assert_equal "+15558675309", form["to"]
    end
  end

  # --- failure modes ---

  test "send_sms raises on a non-2xx response" do
    with_http(401, '{"error":"Unauthorized"}') do
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

  test "send_sms requires the api_key secret" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_key" => "" }).invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
    end
  end

  test "send_sms requires the sid config" do
    assert_raises(Connectors::Error) do
      provider(config: { "sid" => "" }).invoke("send_sms", { "to" => "+15558675309", "text" => "hi" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
