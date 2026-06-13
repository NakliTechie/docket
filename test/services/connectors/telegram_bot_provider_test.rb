require "test_helper"

# Telegram (bot) — effector-only. The bot token rides in the URL PATH, not an
# Authorization header, so the path assertion is the auth assertion here.
# Notifying a configured internal chat is autonomous (like Slack).
class Connectors::TelegramBotProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: { "chat_id" => "-1001234567890" }.merge(config))
    conn.credentials_hash = { "bot_token" => "123456:ABCDEF" }.merge(creds)
    Connectors::TelegramBotProvider.new(conn)
  end

  # --- decision class ---

  test "send_message notifies a configured chat → autonomous" do
    assert_equal :autonomous, Connectors::TelegramBotProvider.action("send_message").effective_decision_class
    refute Connectors::TelegramBotProvider.action("send_message").requires_approval?
  end

  # --- send_message ---

  test "send_message POSTs JSON to /bot<token>/sendMessage with the configured chat_id" do
    with_http(200, '{"ok":true,"result":{"message_id":42}}') do |reqs|
      obs = provider.invoke("send_message", { "text" => "Build green" })
      assert obs["ok"]
      assert_equal 42, obs["result"]["result"]["message_id"]
      assert_equal 42, obs["message_id"], "the sent message id is surfaced for the reply-out loop (L5)"

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/bot123456:ABCDEF/sendMessage", req.path
      body = JSON.parse(req.body)
      assert_equal "-1001234567890", body["chat_id"]
      assert_equal "Build green", body["text"]
      # Auth is the path, not a header.
      assert_nil req["Authorization"]
    end
  end

  test "send_message prefers an explicit chat_id arg over the configured default" do
    with_http(200, '{"ok":true,"result":{"message_id":7}}') do |reqs|
      provider.invoke("send_message", { "text" => "hi", "chat_id" => "999" })
      assert_equal "999", JSON.parse(reqs.last.last.body)["chat_id"]
    end
  end

  test "send_message honours a custom base_url" do
    with_http(200, '{"ok":true}') do |reqs|
      prov = provider(config: { "base_url" => "https://tg.example.com" })
      obs = prov.invoke("send_message", { "text" => "hi" })
      assert obs["ok"]
      assert_equal "/bot123456:ABCDEF/sendMessage", reqs.last.last.path
    end
  end

  test "a non-2xx response raises Connectors::Error" do
    with_http(401, '{"ok":false,"description":"Unauthorized"}') do
      assert_raises(Connectors::Error) { provider.invoke("send_message", { "text" => "hi" }) }
    end
  end

  test "missing text raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("send_message", {}) }
  end

  test "missing chat_id (no arg, no config) raises Connectors::Error" do
    prov = provider(config: { "chat_id" => "" })
    assert_raises(Connectors::Error) { prov.invoke("send_message", { "text" => "hi" }) }
  end

  test "missing bot_token raises Connectors::Error" do
    prov = provider(creds: { "bot_token" => "" })
    assert_raises(Connectors::Error) { prov.invoke("send_message", { "text" => "hi" }) }
  end

  test "an unknown action raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
