require "test_helper"

# Google Chat (incoming webhook) — effector-only. Like Slack, the secret IS the
# webhook URL (it embeds a key + token), so there is no Authorization header;
# the URL assertion is the auth assertion here. Notifying a configured space is
# autonomous. Network is stubbed; the provider isn't in the registry yet, so the
# connector uses a registered provider key ("http_json") as a vault-safe shell.
class Connectors::GoogleChatWebhookProviderTest < ActiveSupport::TestCase
  WEBHOOK = "https://chat.googleapis.com/v1/spaces/AAAA/messages?key=KKK&token=TTT".freeze

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

  def provider(webhook: WEBHOOK)
    conn = Connector.new(provider: "http_json", name: "Staff Chat")
    conn.credentials_hash = { "webhook_url" => webhook } if webhook
    Connectors::GoogleChatWebhookProvider.new(conn)
  end

  # --- descriptor / effector-only ---

  test "descriptor declares an effector-only webhook provider" do
    desc = Connectors::GoogleChatWebhookProvider.descriptor
    assert_equal "googlechat_webhook", desc.key
    assert_equal "Communications", desc.category
    assert_equal %w[webhook_url], desc.secret_fields
    assert_not desc.syncs?
  end

  test "fetch never pulls records" do
    assert_equal [], provider.fetch
  end

  # --- decision class ---

  test "post_message notifies a configured space → autonomous" do
    action = Connectors::GoogleChatWebhookProvider.action("post_message")
    assert_equal :autonomous, action.effective_decision_class
    refute action.requires_approval?
  end

  # --- post_message ---

  test "post_message POSTs {text} JSON to the webhook URL with no auth header" do
    with_http(200, '{"name":"spaces/AAAA/messages/BBBB"}') do |reqs|
      obs = provider.invoke("post_message", { "text" => "Case DKT-1 escalated" })
      assert obs["ok"]
      assert_equal "spaces/AAAA/messages/BBBB", obs["result"]["name"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/v1/spaces/AAAA/messages?key=KKK&token=TTT", req.path
      assert_equal "Case DKT-1 escalated", JSON.parse(req.body)["text"]
      # Auth is the URL token, not a header.
      assert_nil req["Authorization"]
    end
  end

  test "post_message accepts a symbol-keyed text arg" do
    with_http(200) do |reqs|
      provider.invoke("post_message", { text: "hi" })
      assert_equal "hi", JSON.parse(reqs.last.last.body)["text"]
    end
  end

  test "a non-2xx response raises Connectors::Error" do
    with_http(403, '{"error":"forbidden"}') do
      assert_raises(Connectors::Error) { provider.invoke("post_message", { "text" => "hi" }) }
    end
  end

  test "missing text raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("post_message", {}) }
    assert_raises(Connectors::Error) { provider.invoke("post_message", { "text" => "   " }) }
  end

  test "missing webhook_url raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider(webhook: nil).invoke("post_message", { "text" => "hi" }) }
  end

  test "post_message requires an https webhook and is SSRF-guarded" do
    insecure = provider(webhook: "http://chat.googleapis.com/v1/spaces/X/messages")
    err = assert_raises(Connectors::Error) { insecure.invoke("post_message", { "text" => "x" }) }
    assert_includes err.message, "https"

    ssrf = provider(webhook: "https://169.254.169.254/v1/spaces/X/messages")
    blocked = assert_raises(Connectors::Error) { ssrf.invoke("post_message", { "text" => "x" }) }
    assert_includes blocked.message, "blocked"
  end

  test "an unknown action raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
