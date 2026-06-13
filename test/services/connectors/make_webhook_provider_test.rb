require "test_helper"

# Make (webhook) — effector-only. The secret hook_url IS the endpoint: there is
# NO Authorization header, so the absence of auth + the POSTed JSON body are the
# assertions here. Triggering an opaque downstream scenario is discretionary →
# :confirm (a human confirms before it fires), unlike a plain staff notify.
class Connectors::MakeWebhookProviderTest < ActiveSupport::TestCase
  HOOK = "https://hook.eu1.make.com/abcdef123456".freeze

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

  def provider(hook: HOOK)
    conn = Connector.new(provider: "http_json", name: "Make scenario")
    conn.credentials_hash = hook ? { "hook_url" => hook } : {}
    Connectors::MakeWebhookProvider.new(conn)
  end

  # --- descriptor ---

  test "descriptor: effector-only, hook_url secret, Automation category" do
    desc = Connectors::MakeWebhookProvider.descriptor
    assert_equal "make_webhook", desc.key
    assert_equal "Automation", desc.category
    assert_equal %w[hook_url], desc.secret_fields
    assert_empty desc.config_fields
    refute desc.syncs?
  end

  test "effector-only: fetch returns []" do
    assert_equal [], provider.fetch
  end

  # --- decision class ---

  test "trigger_scenario hands off to an opaque automation → confirm" do
    action = Connectors::MakeWebhookProvider.action("trigger_scenario")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
    refute action.of_record?
  end

  # --- trigger_scenario ---

  test "trigger_scenario POSTs the payload JSON to the hook_url with no auth header" do
    with_http(200, '{"status":"accepted"}') do |reqs|
      obs = provider.invoke("trigger_scenario", { "payload" => { "case_id" => "DKT-1", "stage" => "escalated" } })
      assert obs["ok"]
      assert_equal "accepted", obs["result"]["status"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/abcdef123456", req.path
      body = JSON.parse(req.body)
      assert_equal "DKT-1", body["case_id"]
      assert_equal "escalated", body["stage"]
      # The secret IS the URL — there is no Authorization header.
      assert_nil req["Authorization"]
    end
  end

  test "trigger_scenario accepts a symbol-keyed payload arg" do
    with_http(200) do |reqs|
      provider.invoke("trigger_scenario", { payload: { "x" => 1 } })
      assert_equal 1, JSON.parse(reqs.last.last.body)["x"]
    end
  end

  test "trigger_scenario returns the raw body when the response is not JSON" do
    with_http(200, "Accepted") do
      obs = provider.invoke("trigger_scenario", { "payload" => {} })
      assert_equal "Accepted", obs["result"]
    end
  end

  test "a non-2xx response raises Connectors::Error" do
    with_http(400, '{"error":"bad bundle"}') do
      assert_raises(Connectors::Error) { provider.invoke("trigger_scenario", { "payload" => {} }) }
    end
  end

  test "a missing payload raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("trigger_scenario", {}) }
  end

  test "a non-object payload raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("trigger_scenario", { "payload" => "nope" }) }
  end

  test "a missing hook_url raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider(hook: nil).invoke("trigger_scenario", { "payload" => {} }) }
  end

  test "a non-https hook_url is rejected" do
    err = assert_raises(Connectors::Error) do
      provider(hook: "ftp://hook.make.com/x").invoke("trigger_scenario", { "payload" => {} })
    end
    assert_includes err.message, "http"
  end

  test "an SSRF-blocked hook_url is rejected" do
    err = assert_raises(Connectors::Error) do
      provider(hook: "https://169.254.169.254/latest").invoke("trigger_scenario", { "payload" => {} })
    end
    assert_includes err.message, "blocked"
  end

  test "an unknown action raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
