require "test_helper"

# Slice 2: the effector orchestration — authorize → idempotency → approval
# gate → execute (agent as audit actor) → record observation. Drives the
# real http_json post_json action with the network stubbed.
class Connectors::InvokeTest < ActiveSupport::TestCase
  def connector(enabled: %w[post_json], auto_approve: [])
    Connector.create!(name: "Effector", provider: "http_json", target: "contacts",
      config: { "action_url" => "https://api.example.com/do" },
      field_mapping: { "external_id" => "id" },
      enabled_actions: enabled, auto_approve_actions: auto_approve)
  end

  def agent(scopes: %w[connectors:invoke])
    ServiceAccount.create!(name: "Triage agent", scopes: scopes)
  end

  def staff(role: :supervisor)
    User.create!(name: "Sup", email_address: "sup-#{SecureRandom.hex(4)}@x.test",
                 password: "password123", role: role)
  end

  # --- network stub (mirrors sync_test) ---
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

  def args = { "body" => { "case" => "C-1" } }

  # --- approval gate ---

  test "a write action parks as proposed when the connector does not auto-approve" do
    conn = connector(auto_approve: [])
    inv = Connectors::Invoke.call(conn, "post_json", args: args, principal: agent)
    assert inv.status_proposed?
    assert_nil inv.result
    assert_nil inv.finished_at
  end

  test "a write action the connector auto-approves executes immediately" do
    conn = connector(auto_approve: %w[post_json])
    inv = with_http(FakeResponse.new("200", '{"ok":true,"ref":"R-7"}')) do
      Connectors::Invoke.call(conn, "post_json", args: args, principal: agent)
    end
    assert inv.status_succeeded?
    assert_equal 200, inv.result["http_status"]
    assert_equal "R-7", inv.result["body"]["ref"]
    assert inv.finished_at.present?
  end

  test "approve! releases a parked invocation and executes it" do
    conn = connector
    inv = Connectors::Invoke.call(conn, "post_json", args: args, principal: agent)
    assert inv.status_proposed?

    approver = staff
    with_http(FakeResponse.new("200", '{"ok":true}')) do
      Connectors::Invoke.approve!(inv, approver: approver)
    end
    assert inv.reload.status_succeeded?
    assert_equal approver, inv.approved_by
    assert inv.approved_at.present?
  end

  test "reject! kills a parked invocation without executing" do
    inv = Connectors::Invoke.call(connector, "post_json", args: args, principal: agent)
    approver = staff
    Connectors::Invoke.reject!(inv, approver: approver)
    assert inv.reload.status_rejected?
    assert_nil inv.result
  end

  # --- idempotency ---

  test "the same idempotency key returns the original invocation, never a duplicate" do
    conn = connector
    first = Connectors::Invoke.call(conn, "post_json", args: args, principal: agent, idempotency_key: "k-1")
    assert_no_difference "ConnectorInvocation.count" do
      again = Connectors::Invoke.call(conn, "post_json", args: args, principal: agent, idempotency_key: "k-1")
      assert_equal first.id, again.id
    end
  end

  # --- authorization (deny by default) ---

  test "a principal without connectors:invoke is forbidden" do
    conn = connector
    powerless = agent(scopes: %w[contacts:read])
    assert_raises(Connectors::Authorization::Forbidden) do
      Connectors::Invoke.call(conn, "post_json", args: args, principal: powerless)
    end
  end

  test "an action the connector does not expose is forbidden" do
    conn = connector(enabled: [])
    assert_raises(Connectors::Authorization::Forbidden) do
      Connectors::Invoke.call(conn, "post_json", args: args, principal: agent)
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) do
      Connectors::Invoke.call(connector, "teleport", args: {}, principal: agent)
    end
  end

  # --- failure is recorded, not raised, so the agent can read it ---

  test "a provider failure marks the invocation failed with the error" do
    conn = connector(auto_approve: %w[post_json])
    inv = with_http(FakeResponse.new("503", "down")) do
      Connectors::Invoke.call(conn, "post_json", args: args, principal: agent)
    end
    assert inv.status_failed?
    assert_includes inv.error, "503"
  end

  # --- audit attribution: the agent is the actor; payload is redacted ---

  test "the execution is attributed to the agent in the audit chain, args/result redacted" do
    conn = connector(auto_approve: %w[post_json])
    a = agent
    inv = with_http(FakeResponse.new("200", '{"secret":"xyz"}')) do
      Connectors::Invoke.call(conn, "post_json", args: args, principal: a)
    end
    entry = AuditEntry.where(auditable_type: "ConnectorInvocation", auditable_id: inv.id).order(:id).last
    assert_equal a, entry.actor
    # args/result must never enter the hash chain in cleartext
    assert_not_includes entry.changeset.to_s, "xyz"
    assert_not_includes entry.changeset.to_s, "C-1"
  end
end
