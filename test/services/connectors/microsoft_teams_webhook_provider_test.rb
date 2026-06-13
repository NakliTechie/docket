require "test_helper"

# Microsoft Teams (incoming webhook) — effector-only. Like Slack: the secret
# webhook_url IS the full HTTPS endpoint, so there is NO Authorization header
# and the URL is the auth. Notifying a configured channel is autonomous.
class Connectors::MicrosoftTeamsWebhookProviderTest < ActiveSupport::TestCase
  WEBHOOK = "https://example.webhook.office.com/webhookb2/abc/IncomingWebhook/def/ghi".freeze

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
  def with_http(code, body = "1")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def provider(webhook: WEBHOOK)
    conn = Connector.new(provider: "http_json", name: "Staff Teams")
    conn.credentials_hash = { "webhook_url" => webhook }
    Connectors::MicrosoftTeamsWebhookProvider.new(conn)
  end

  # --- descriptor / capability surface ---

  test "descriptor is effector-only with a single webhook_url secret" do
    desc = Connectors::MicrosoftTeamsWebhookProvider.descriptor
    assert_equal "msteams_webhook", desc.key
    assert_equal "Communications", desc.category
    assert_not desc.syncs?
    assert_equal %w[webhook_url], desc.secret_fields
    assert_equal [], desc.config_fields
  end

  test "post_message notifies a configured channel → autonomous" do
    action = Connectors::MicrosoftTeamsWebhookProvider.action("post_message")
    assert_equal :write, action.effect
    assert_equal :autonomous, action.effective_decision_class
    assert_not action.requires_approval?
  end

  # --- effector-only: never syncs ---

  test "fetch returns no records (effector-only)" do
    assert_equal [], provider.fetch
  end

  # --- post_message (network stubbed) ---

  test "post_message POSTs JSON {text} to the webhook and returns an observation" do
    with_http(200) do |reqs|
      obs = provider.invoke("post_message", { "text" => "Case DKT-1 escalated" })
      assert obs["ok"]
      assert_equal "Case DKT-1 escalated", obs["posted"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "Case DKT-1 escalated", JSON.parse(req.body)["text"]
      # Auth is the URL, not a header.
      assert_nil req["Authorization"]
    end
  end

  test "post_message accepts a symbol-keyed text arg" do
    with_http(200) do |reqs|
      provider.invoke("post_message", { text: "hi there" })
      assert_equal "hi there", JSON.parse(reqs.last.last.body)["text"]
    end
  end

  test "a non-2xx response raises Connectors::Error" do
    with_http(400, "Bad payload") do
      assert_raises(Connectors::Error) { provider.invoke("post_message", { "text" => "hi" }) }
    end
  end

  test "missing text raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("post_message", {}) }
  end

  test "blank text raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("post_message", { "text" => "   " }) }
  end

  test "missing webhook_url raises Connectors::Error" do
    err = assert_raises(Connectors::Error) { provider(webhook: "").invoke("post_message", { "text" => "hi" }) }
    assert_includes err.message, "webhook_url"
  end

  test "post_message requires an https webhook" do
    prov = provider(webhook: "http://example.webhook.office.com/webhookb2/abc")
    err = assert_raises(Connectors::Error) { prov.invoke("post_message", { "text" => "hi" }) }
    assert_includes err.message, "https"
  end

  test "post_message is SSRF-guarded" do
    prov = provider(webhook: "https://169.254.169.254/webhookb2/abc")
    err = assert_raises(Connectors::Error) { prov.invoke("post_message", { "text" => "hi" }) }
    assert_includes err.message, "blocked"
  end

  test "an unknown action raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
