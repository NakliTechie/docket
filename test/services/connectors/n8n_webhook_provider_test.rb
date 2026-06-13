require "test_helper"

# n8n (webhook) — effector-only Automation provider. The secret webhook_url IS
# the endpoint (no auth header). Triggering a workflow is a :confirm write.
#
# The registry wiring for "n8n_webhook" is added centrally by the orchestrator,
# so this test instantiates the provider class directly against a placeholder
# Connector (mirroring the Twilio test) rather than going through the registry.
class Connectors::N8nWebhookProviderTest < ActiveSupport::TestCase
  HOOK = "https://n8n.internal.example/webhook/abc-123".freeze

  # --- capturing HTTP stub (same shape as the other provider tests) ---
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

  def provider(webhook: HOOK)
    # http_json is a registered provider, so Connector#new validates; we only
    # use it as a credential carrier and instantiate the n8n class directly.
    conn = Connector.new(provider: "http_json", name: "Ops automation")
    conn.credentials_hash = { "webhook_url" => webhook } if webhook
    Connectors::N8nWebhookProvider.new(conn)
  end

  RESULT_BODY = '{"message":"Workflow was started"}'.freeze

  # --- descriptor ---

  test "descriptor declares an effector-only Automation provider keyed on the webhook_url secret" do
    d = Connectors::N8nWebhookProvider.descriptor
    assert_equal "n8n_webhook", d.key
    assert_equal "n8n (webhook)", d.name
    assert_equal "Automation", d.category
    assert_not d.syncs?
    assert_equal %w[webhook_url], d.secret_fields
    assert_equal [], d.config_fields
  end

  # --- decision class ---

  test "trigger_workflow is a :confirm write (a human confirms before the workflow fires)" do
    action = Connectors::N8nWebhookProvider.action("trigger_workflow")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  test "the action declares payload as a required object param" do
    action = Connectors::N8nWebhookProvider.action("trigger_workflow")
    assert_equal %w[payload], action.params["required"]
    assert_equal "object", action.params.dig("properties", "payload", "type")
  end

  # --- effector-only: never syncs ---

  test "effector-only provider inherits an empty fetch" do
    assert_equal [], provider.fetch
  end

  # --- trigger_workflow (network stubbed) ---

  test "trigger_workflow POSTs the payload to the webhook_url and returns the parsed observation" do
    with_http(200, RESULT_BODY) do |reqs|
      obs = provider.invoke("trigger_workflow", { "payload" => { "case_id" => "DKT-1", "stage" => "escalated" } })
      assert obs["ok"]
      assert_equal "Workflow was started", obs["result"]["message"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/webhook/abc-123", req.path
      assert_equal "application/json", req["Content-Type"]
      assert_equal({ "case_id" => "DKT-1", "stage" => "escalated" }, JSON.parse(req.body))
    end
  end

  test "trigger_workflow accepts symbol-keyed args" do
    with_http(200, RESULT_BODY) do |reqs|
      obs = provider.invoke("trigger_workflow", { payload: { "k" => "v" } })
      assert obs["ok"]
      assert_equal({ "k" => "v" }, JSON.parse(reqs.last.last.body))
    end
  end

  test "trigger_workflow sends no Authorization header (the URL is the credential)" do
    with_http(200, RESULT_BODY) do |reqs|
      provider.invoke("trigger_workflow", { "payload" => {} })
      assert_nil reqs.last.last["Authorization"]
    end
  end

  # --- failure modes ---

  test "trigger_workflow raises on a non-2xx response" do
    with_http(500, '{"message":"boom"}') do
      err = assert_raises(Connectors::Error) { provider.invoke("trigger_workflow", { "payload" => {} }) }
      assert_includes err.message, "n8n"
    end
  end

  test "trigger_workflow requires a payload object" do
    with_http(200, RESULT_BODY) do
      assert_raises(Connectors::Error) { provider.invoke("trigger_workflow", {}) }
      assert_raises(Connectors::Error) { provider.invoke("trigger_workflow", { "payload" => "not-an-object" }) }
    end
  end

  test "trigger_workflow requires the webhook_url secret" do
    assert_raises(Connectors::Error) do
      provider(webhook: nil).invoke("trigger_workflow", { "payload" => {} })
    end
  end

  test "trigger_workflow is SSRF-guarded against the cloud-metadata endpoint" do
    err = assert_raises(Connectors::Error) do
      provider(webhook: "https://169.254.169.254/webhook/x").invoke("trigger_workflow", { "payload" => {} })
    end
    assert_includes err.message, "blocked"
  end

  test "trigger_workflow rejects a non-http(s) webhook scheme" do
    assert_raises(Connectors::Error) do
      provider(webhook: "ftp://n8n.internal/webhook/x").invoke("trigger_workflow", { "payload" => {} })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
