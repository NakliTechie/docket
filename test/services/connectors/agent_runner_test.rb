require "test_helper"

# Slice B: the dispatch loop. Drives the FakeClient (which calls the first
# offered tool once, then stops) over the real effector gate.
class Connectors::AgentRunnerTest < ActiveSupport::TestCase
  def kase
    cases(:pension_case)
  end

  def agent(scopes: %w[connectors:invoke])
    ServiceAccount.create!(name: "Case agent", scopes: scopes)
  end

  def connector(auto_approve: [])
    Connector.create!(name: "Records API", provider: "http_json", target: "contacts",
      config: { "action_url" => "https://api.example.com/do" },
      field_mapping: { "external_id" => "id" },
      enabled_actions: %w[post_json], auto_approve_actions: auto_approve)
  end

  # network stub for the auto-approve/execute path
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(_) = @r
  end
  def with_http(resp)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(resp) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def run!(principal = agent, client: Llm::FakeClient.new)
    Connectors::AgentRunner.new(kase, agent: principal, client: client).run
  end

  def effector_notes
    kase.messages.reload.select { |m| m.metadata&.dig("ai") == "effector" }
  end

  test "a write action the agent calls is queued for approval, not executed" do
    connector # no auto-approve -> post_json (confirm) parks proposed
    a = agent
    assert_difference("ConnectorInvocation.count", 1) { run!(a) }

    inv = ConnectorInvocation.last
    assert inv.status_proposed?
    assert_equal a, inv.requested_by
    assert_equal "case:#{kase.id}", inv.on_behalf_of

    assert effector_notes.any? { |m| m.metadata["status"] == "proposed" }, "expected a queued step note"
    assert effector_notes.any? { |m| m.metadata["summary"] }, "expected a final summary note"
  end

  test "an auto-approved action executes and feeds the result back" do
    connector(auto_approve: %w[post_json])
    with_http(FakeResponse.new("200", '{"ok":true}')) { run! }

    inv = ConnectorInvocation.last
    assert inv.status_succeeded?
    assert effector_notes.any? { |m| m.metadata["status"] == "succeeded" }
  end

  test "an agent without connectors:invoke does nothing" do
    connector
    assert_no_difference("ConnectorInvocation.count") { run!(agent(scopes: %w[contacts:read])) }
    assert_empty effector_notes
  end

  test "a connector with no enabled actions offers no tools — the loop is a no-op" do
    Connector.create!(name: "Idle", provider: "http_json", target: "contacts",
      config: {}, field_mapping: { "external_id" => "id" }, enabled_actions: [])
    assert_no_difference("ConnectorInvocation.count") { run! }
  end

  test "repeated identical calls are idempotent — no duplicate invocation" do
    connector
    a = agent
    run!(a)
    assert_no_difference("ConnectorInvocation.count") { run!(a) } # same case+tool+args -> same key
  end

  test "no client (AI disabled) is a no-op" do
    connector
    assert_no_difference("ConnectorInvocation.count") do
      Connectors::AgentRunner.new(kase, agent: agent, client: nil).run
    end
  end
end
