require "test_helper"

# Decision-class tagging: the accountability tier (Indian admin-law boundary)
# that drives the gate. autonomous runs unattended; confirm parks for a human;
# of_record always needs a human + a reasoned order and can never be
# auto-approved.
class Connectors::DecisionClassTest < ActiveSupport::TestCase
  Action = Connectors::Provider::Action

  def build_action(effect: :write, decision_class: nil)
    Action.new(key: "act", name: "Act", summary: "s", params: {},
               effect: effect, decision_class: decision_class)
  end

  def connector(auto_approve: [])
    Connector.create!(name: "E", provider: "http_json", target: "contacts",
      config: {}, field_mapping: { "external_id" => "id" },
      enabled_actions: %w[act], auto_approve_actions: auto_approve)
  end

  def agent
    ServiceAccount.create!(name: "A", scopes: %w[connectors:invoke])
  end

  def staff
    User.create!(name: "Sup", email_address: "s-#{SecureRandom.hex(4)}@x.test",
                 password: "password123", role: :supervisor)
  end

  # Stub the action lookup + execution so we test the gate, not a provider.
  def stub(conn, action)
    conn.define_singleton_method(:provider_action) { |_k| action }
    fake = Object.new
    fake.define_singleton_method(:invoke) { |_k, _a, _c| { "ok" => true } }
    conn.define_singleton_method(:provider_instance) { fake }
  end

  def call(conn)
    Connectors::Invoke.call(conn, "act", args: { "x" => 1 }, principal: agent, on_behalf_of: "case:1")
  end

  # --- derivation from effect ---

  test "decision_class defaults from effect when undeclared" do
    assert_equal :autonomous, build_action(effect: :read).effective_decision_class
    assert_equal :confirm,    build_action(effect: :write).effective_decision_class
    assert_equal :of_record,  build_action(effect: :irreversible).effective_decision_class
  end

  test "an explicit decision_class overrides the effect default" do
    # an irreversible action a human need only confirm, not own of record
    a = build_action(effect: :irreversible, decision_class: :confirm)
    assert_equal :confirm, a.effective_decision_class
    assert_not a.of_record?
    # a reversible write that is nonetheless an adverse decision of record
    b = build_action(effect: :write, decision_class: :of_record)
    assert b.of_record?
    assert b.requires_approval?
  end

  # --- gate routing ---

  test "an autonomous action runs unattended" do
    conn = connector
    stub(conn, build_action(effect: :read)) # → autonomous
    inv = call(conn)
    assert inv.status_succeeded?
    assert_equal "autonomous", inv.decision_class
  end

  test "a decision of record always parks for a human — auto-approve cannot bypass it" do
    conn = connector(auto_approve: %w[act])
    stub(conn, build_action(decision_class: :of_record))
    inv = call(conn)
    assert inv.status_proposed?
    assert_equal "of_record", inv.decision_class
  end

  test "a confirm action respects the connector's auto-approve list" do
    conn = connector(auto_approve: %w[act])
    stub(conn, build_action(effect: :write)) # → confirm
    inv = call(conn)
    assert inv.status_succeeded?
  end

  # --- reasoned order for decisions of record ---

  test "approving a decision of record requires a reasoned order" do
    conn = connector
    stub(conn, build_action(decision_class: :of_record))
    inv = call(conn)
    assert inv.status_proposed?

    err = assert_raises(Connectors::Error) { Connectors::Invoke.approve!(inv, approver: staff, reason: "  ") }
    assert_includes err.message, "reasoned order"
    assert inv.status_proposed? # raised before any mutation; no reload (it would drop the stub)

    Connectors::Invoke.approve!(inv, approver: staff, reason: "Eligibility verified against records")
    assert inv.reload.status_succeeded?
    assert_equal "Eligibility verified against records", inv.decision_reason
    assert inv.contestable?
  end

  test "a confirm decision may be approved without a reason" do
    conn = connector
    stub(conn, build_action(effect: :write)) # → confirm
    inv = call(conn)
    assert_nothing_raised { Connectors::Invoke.approve!(inv, approver: staff) }
    assert inv.reload.status_succeeded?
    assert_not inv.contestable?
  end
end
