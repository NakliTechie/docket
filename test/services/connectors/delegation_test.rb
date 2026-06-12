require "test_helper"

# Delegation binding: every invocation mints a durable, opaque delegation_id
# bound to its principal, snapshots the action's effect, propagates the id to
# the downstream call, and stamps it into the audit metadata.
class Connectors::DelegationTest < ActiveSupport::TestCase
  def connector(auto_approve: %w[post_json])
    Connector.create!(name: "Effector", provider: "http_json", target: "contacts",
      config: { "action_url" => "https://api.example.com/do" },
      field_mapping: { "external_id" => "id" },
      enabled_actions: %w[post_json], auto_approve_actions: auto_approve)
  end

  def agent
    ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke])
  end

  # --- capturing network stub ---
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class CapturingHttp
    attr_reader :last_request
    def initialize(response) = @response = response
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last_request = req; @response)
  end
  def with_capturing_http(response)
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| CapturingHttp.new(response).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "every invocation mints an opaque, stable, unique delegation_id" do
    inv = Connectors::Invoke.call(connector(auto_approve: []), "post_json",
      args: { "body" => { "x" => 1 } }, principal: agent, on_behalf_of: "case:1")
    assert_match(/\Adlg_[A-Za-z0-9]{24}\z/, inv.delegation_id)
    assert_equal inv.delegation_id, inv.reload.delegation_id

    other = Connectors::Invoke.call(connector(auto_approve: []), "post_json",
      args: { "body" => { "x" => 1 } }, principal: agent, on_behalf_of: "case:2")
    assert_not_equal inv.delegation_id, other.delegation_id
  end

  test "the action's effect is snapshotted onto the invocation" do
    inv = Connectors::Invoke.call(connector(auto_approve: []), "post_json",
      args: { "body" => { "x" => 1 } }, principal: agent, on_behalf_of: "case:1")
    assert_equal "write", inv.effect
  end

  test "the downstream call carries the delegation id as a header" do
    inv = nil
    captured = nil
    with_capturing_http(FakeResponse.new("200", "{}")) do |reqs|
      inv = Connectors::Invoke.call(connector, "post_json",
        args: { "body" => { "x" => 1 } }, principal: agent, on_behalf_of: "case:1")
      captured = reqs
    end
    sent = captured.last.last_request
    assert_equal inv.delegation_id, sent["X-Docket-Delegation-Id"]
  end

  test "audit entries written during execution carry the delegation id" do
    inv = with_capturing_http(FakeResponse.new("200", "{}")) do
      Connectors::Invoke.call(connector, "post_json",
        args: { "body" => { "x" => 1 } }, principal: agent, on_behalf_of: "case:1")
    end
    succeeded = AuditEntry.where(auditable_type: "ConnectorInvocation", auditable_id: inv.id).order(:id).last
    assert_equal inv.delegation_id, succeeded.metadata["delegation_id"]
  end
end
