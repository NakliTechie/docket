require "test_helper"

class Connectors::GupshupProviderTest < ActiveSupport::TestCase
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
                         config: { "source" => "917000000000" }.merge(config))
    conn.credentials_hash = { "api_key" => "key-secret" }.merge(creds)
    Connectors::GupshupProvider.new(conn)
  end

  SENT_BODY = '{"status":"submitted","messageId":"abc-123"}'.freeze

  # --- descriptor / decision-class ---

  test "descriptor declares Gupshup as an effector-only comms provider" do
    d = Connectors::GupshupProvider.descriptor
    assert_equal "gupshup", d.key
    assert_equal "Gupshup (messaging)", d.name
    assert_equal "Communications", d.category
    assert_not d.syncs?
    assert_equal %w[api_key], d.secret_fields
    assert_equal %w[source base_url], d.config_fields
  end

  test "send_message is a :confirm action (a human confirms before a customer send goes out)" do
    action = Connectors::GupshupProvider.action("send_message")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  test "effector-only provider inherits an empty fetch" do
    assert_equal [], provider.fetch
  end

  # --- send_message (network stubbed) ---

  test "send_message posts a form-encoded message and returns the parsed observation" do
    with_http(200, SENT_BODY) do |reqs|
      obs = provider.invoke("send_message", { "to" => "919812345678", "text" => "Your case DKT-1 was updated" })
      assert obs["ok"]
      assert_equal "abc-123", obs["message"]["messageId"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/sm/api/v1/msg", req.path
      assert_equal "application/x-www-form-urlencoded", req["Content-Type"]

      form = URI.decode_www_form(req.body).to_h
      assert_equal "sms", form["channel"]
      assert_equal "917000000000", form["source"]
      assert_equal "919812345678", form["destination"]
      assert_equal "Your case DKT-1 was updated", form["message"]
    end
  end

  test "send_message sends the api_key in the apikey header" do
    with_http(200, SENT_BODY) do |reqs|
      provider.invoke("send_message", { "to" => "919812345678", "text" => "hi" })
      assert_equal "key-secret", reqs.last.last["apikey"]
    end
  end

  test "send_message defaults the channel to sms and honours an override" do
    with_http(200, SENT_BODY) do |reqs|
      provider.invoke("send_message", { "to" => "919812345678", "text" => "hi", "channel" => "whatsapp" })
      assert_equal "whatsapp", URI.decode_www_form(reqs.last.last.body).to_h["channel"]
    end
  end

  test "send_message honours a configured base_url override without erroring" do
    with_http(200, SENT_BODY) do |reqs|
      obs = provider(config: { "base_url" => "https://api.gupshup.test" })
            .invoke("send_message", { "to" => "919812345678", "text" => "hi" })
      assert obs["ok"]
      assert_equal "/sm/api/v1/msg", reqs.last.last.path
    end
  end

  test "send_message accepts symbol-keyed args" do
    with_http(200, SENT_BODY) do |reqs|
      obs = provider.invoke("send_message", { to: "919812345678", text: "hi", channel: "whatsapp" })
      assert obs["ok"]
      form = URI.decode_www_form(reqs.last.last.body).to_h
      assert_equal "919812345678", form["destination"]
      assert_equal "whatsapp", form["channel"]
    end
  end

  # --- failure modes ---

  test "send_message raises on a non-2xx response" do
    with_http(401, '{"message":"Unauthorized"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("send_message", { "to" => "919812345678", "text" => "hi" })
      end
    end
  end

  test "send_message requires a recipient" do
    with_http(200, SENT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("send_message", { "text" => "hi" }) }
    end
  end

  test "send_message requires a body" do
    with_http(200, SENT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("send_message", { "to" => "919812345678" }) }
    end
  end

  test "send_message requires the source config value" do
    with_http(200, SENT_BODY) do
      assert_raises(Connectors::Error) do
        provider(config: { "source" => "" }).invoke("send_message", { "to" => "919812345678", "text" => "hi" })
      end
    end
  end

  test "send_message requires the api_key secret" do
    with_http(200, SENT_BODY) do
      assert_raises(Connectors::Error) do
        provider(creds: { "api_key" => "" }).invoke("send_message", { "to" => "919812345678", "text" => "hi" })
      end
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
