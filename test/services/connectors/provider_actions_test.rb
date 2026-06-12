require "test_helper"

# Slice 1: the agent-facing capability surface on a provider — .actions,
# #invoke, the Action approval signal, and the tool-spec projection. No DB
# effector ledger yet (that's Connectors::Invoke).
class Connectors::ProviderActionsTest < ActiveSupport::TestCase
  def connector(config: { "action_url" => "https://api.example.com/do" })
    Connector.create!(name: "Effector", provider: "http_json", target: "contacts",
                      config: config, field_mapping: { "external_id" => "id" })
  end

  # --- Action approval signal ---

  test "reads run unattended; writes and irreversible actions need approval" do
    read  = Connectors::Provider::Action.new(key: "k", effect: :read)
    write = Connectors::Provider::Action.new(key: "k", effect: :write)
    irrev = Connectors::Provider::Action.new(key: "k", effect: :irreversible)
    assert_not read.requires_approval?
    assert write.requires_approval?
    assert irrev.requires_approval?
  end

  # --- Provider catalogue ---

  test "a sync-only provider exposes no actions by default" do
    assert_equal [], Connectors::Provider.actions
  end

  test "http_json declares a post_json write action and looks it up by key" do
    action = Connectors::HttpJsonProvider.action("post_json")
    assert_equal "post_json", action.key
    assert_equal :write, action.effect
    assert action.requires_approval?
    assert_nil Connectors::HttpJsonProvider.action("nope")
  end

  # --- Tool-spec projection (the admin-form descriptor == the LLM tool spec) ---

  test "Registry.tool_specs projects actions into namespaced Anthropic tool specs" do
    conn = connector
    spec = Connectors::Registry.tool_specs(conn).sole
    assert_equal "conn_#{conn.id}__post_json", spec[:name]
    assert_includes spec[:description], "POST a JSON body"
    assert_equal "object", spec[:input_schema]["type"]
    assert_includes spec[:input_schema]["properties"].keys, "body"
  end

  # --- #invoke (network stubbed) ---

  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end

  class FakeHttp
    def initialize(response) = @response = response
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(_req) = @response
  end

  def with_http(response)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(response) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "post_json returns the response as a structured observation" do
    conn = connector
    with_http(FakeResponse.new("200", '{"ok":true,"ref":"R-7"}')) do
      obs = conn.provider_instance.invoke("post_json", { "body" => { "x" => 1 } })
      assert_equal 200, obs["http_status"]
      assert_equal "R-7", obs["body"]["ref"]
    end
  end

  test "post_json requires a hash body" do
    conn = connector
    assert_raises(Connectors::Error) { conn.provider_instance.invoke("post_json", {}) }
  end

  test "post_json is SSRF-guarded on the action_url" do
    conn = connector(config: { "action_url" => "http://169.254.169.254/latest" })
    error = assert_raises(Connectors::Error) do
      conn.provider_instance.invoke("post_json", { "body" => { "x" => 1 } })
    end
    assert_includes error.message, "blocked"
  end

  test "an unknown action raises" do
    conn = connector
    assert_raises(Connectors::Error) { conn.provider_instance.invoke("teleport", {}) }
  end

  # --- The agent's authority is a ServiceAccount scope ---

  test "connectors:invoke is a recognised ServiceAccount scope" do
    agent = ServiceAccount.create!(name: "Triage agent", scopes: %w[contacts:read connectors:invoke])
    assert agent.scope?("connectors:invoke")
    assert agent.persisted?
  end
end
