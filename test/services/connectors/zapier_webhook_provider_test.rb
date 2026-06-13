require "test_helper"

# Effector-only Zapier "catch hook" provider: the secret hook_url IS the
# endpoint; one confirm-class write action POSTs an arbitrary JSON payload.
class Connectors::ZapierWebhookProviderTest < ActiveSupport::TestCase
  HOOK = "https://hooks.zapier.com/hooks/catch/123456/abcdef/".freeze

  def zapier_connector(hook: HOOK)
    conn = Connector.create!(name: "Ops Zap", provider: "zapier_webhook")
    if hook
      conn.credentials_hash = { "hook_url" => hook }
      conn.save!
    end
    conn
  end

  # --- capturing HTTP stub ---
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
  def with_http(code, body = "{\"status\":\"success\"}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  # --- descriptor / registration ---

  test "zapier_webhook is registered, effector-only, and declares the hook_url secret" do
    assert Connectors::Registry.key?("zapier_webhook")
    assert_not Connectors::ZapierWebhookProvider.descriptor.syncs?
    assert_equal %w[hook_url], Connectors::ZapierWebhookProvider.descriptor.secret_fields
    assert_equal [], Connectors::ZapierWebhookProvider.new(zapier_connector(hook: nil)).fetch
  end

  test "an effector-only connector saves with no field mapping" do
    conn = Connector.create!(name: "Ops Zap", provider: "zapier_webhook")
    assert conn.persisted?
    assert_not conn.provider_syncs?
  end

  # --- decision class ---

  test "trigger_zap is a confirm action (external automation, needs a human)" do
    action = Connectors::ZapierWebhookProvider.action("trigger_zap")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
    assert_not action.of_record?
  end

  # --- the action itself (network stubbed) ---

  test "trigger_zap posts the payload object to the hook and returns an observation" do
    conn = zapier_connector
    with_http(200) do |reqs|
      obs = conn.provider_instance.invoke("trigger_zap", { "payload" => { "case" => "DKT-1", "n" => 2 } })
      assert obs["ok"]
      assert_equal({ "case" => "DKT-1", "n" => 2 }, JSON.parse(reqs.last.last.body))
      assert_equal "success", obs["result"]["status"]
    end
  end

  test "trigger_zap accepts a symbol-keyed payload arg" do
    conn = zapier_connector
    with_http(200) do |reqs|
      obs = conn.provider_instance.invoke("trigger_zap", { payload: { "x" => 1 } })
      assert obs["ok"]
      assert_equal({ "x" => 1 }, JSON.parse(reqs.last.last.body))
    end
  end

  test "trigger_zap requires a payload object" do
    conn = zapier_connector
    assert_raises(Connectors::Error) { conn.provider_instance.invoke("trigger_zap", {}) }
    # a non-object payload (e.g. a bare string) is rejected
    assert_raises(Connectors::Error) { conn.provider_instance.invoke("trigger_zap", { "payload" => "nope" }) }
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { zapier_connector.provider_instance.invoke("nope", {}) }
  end

  test "a non-2xx response from Zapier raises" do
    conn = zapier_connector
    with_http(410, "Gone") do
      assert_raises(Connectors::Error) { conn.provider_instance.invoke("trigger_zap", { "payload" => { "a" => 1 } }) }
    end
  end

  # --- secret + SSRF / https guards ---

  test "a missing hook_url raises" do
    conn = zapier_connector(hook: nil)
    assert_raises(Connectors::Error) { conn.provider_instance.invoke("trigger_zap", { "payload" => { "a" => 1 } }) }
  end

  test "trigger_zap requires an https hook and is SSRF-guarded" do
    http_conn = zapier_connector(hook: "http://hooks.zapier.com/hooks/catch/1/x/")
    assert_raises(Connectors::Error) { http_conn.provider_instance.invoke("trigger_zap", { "payload" => { "a" => 1 } }) }

    ssrf = zapier_connector(hook: "https://169.254.169.254/hooks/catch/1/x/")
    err = assert_raises(Connectors::Error) { ssrf.provider_instance.invoke("trigger_zap", { "payload" => { "a" => 1 } }) }
    assert_includes err.message, "blocked"
  end

  test "the hook_url secret round-trips through the encrypted vault" do
    conn = zapier_connector
    assert_equal HOOK, conn.reload.credentials_hash["hook_url"]
  end
end
