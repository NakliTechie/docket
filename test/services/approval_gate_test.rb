require "test_helper"

# PG4 — maker-checker enforcement: guarded case transitions and effector-action
# escalation, plus the approve (reasoned order) / reject decisions.
class ApprovalGateTest < ActiveSupport::TestCase
  def resolved_case
    kase = Case.create!(subject: "Refund dispute", channel: :staff, contact: contacts(:asha))
    kase.transition_to!(:triaged)
    kase.transition_to!(:resolved)
    kase
  end

  def closure_process
    ApprovalProcess.create!(name: "Closure sign-off", trigger_type: :case_transition, trigger_key: "closed")
  end

  test "for_transition / for_action find the active process by trigger" do
    p = closure_process
    assert_equal p, ApprovalProcess.for_transition("closed")
    assert_nil ApprovalProcess.for_transition("resolved")
    p.update!(active: false)
    assert_nil ApprovalProcess.for_transition("closed"), "inactive processes don't gate"
  end

  test "a guarded transition is not cleared until an approved request exists" do
    kase = resolved_case
    closure_process
    assert ApprovalGate.guarded_transition?(kase, "closed")
    refute ApprovalGate.transition_cleared?(kase, "closed")
  end

  test "submit_transition! parks one idempotent pending request" do
    kase = resolved_case
    closure_process
    a = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))
    b = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))
    assert_equal a.id, b.id
    assert a.status_pending?
    assert_equal 1, kase.approval_requests.count
  end

  test "approve requires a reasoned order, then performs the transition" do
    kase = resolved_case
    closure_process
    req = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))

    assert_raises(ApprovalGate::Error) { ApprovalGate.approve!(req, approver: users(:client_admin), reason: " ") }

    ApprovalGate.approve!(req, approver: users(:client_admin), reason: "Verified resolution with citizen.")
    assert req.reload.status_approved?
    assert_equal users(:client_admin), req.decided_by
    assert kase.reload.status_closed?, "approval performs the guarded transition"
  end

  test "reject blocks the transition; the case stays put" do
    kase = resolved_case
    closure_process
    req = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))
    ApprovalGate.reject!(req, approver: users(:client_admin), reason: "Open complaint unresolved.")
    assert req.reload.status_rejected?
    assert kase.reload.status_resolved?, "a rejected case does not close"
  end

  test "an approval process escalates an otherwise-autonomous effector action to review" do
    slack = Connector.create!(name: "S", provider: "slack_webhook", status: :active,
                              credentials_hash: { "webhook_url" => "https://hooks.slack.com/x" })
    action = slack.provider_action("post_message")
    assert_equal :approved, Connectors::Invoke.gated_status(slack, action), "autonomous → runs unattended by default"

    ApprovalProcess.create!(name: "Review Slack posts", trigger_type: :effector_action, trigger_key: "post_message")
    assert_equal :proposed, Connectors::Invoke.gated_status(slack, action), "the process forces human review"
  end

  test "a case_transition process rejects a trigger_key that isn't a real status" do
    refute ApprovalProcess.new(name: "x", trigger_type: :case_transition, trigger_key: "nonsense").valid?
    assert ApprovalProcess.new(name: "x", trigger_type: :case_transition, trigger_key: "closed").valid?
  end

  test "an approval is consumed, so a later guarded transition needs fresh sign-off (H4)" do
    closure_process
    kase = resolved_case
    req = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))
    ApprovalGate.approve!(req, approver: users(:client_admin), reason: "First closure verified.")
    assert kase.reload.status_closed?
    assert req.reload.consumed_at.present?, "the acted-on approval is marked spent"

    # The spent approval must NOT clear a future closure.
    refute ApprovalGate.transition_cleared?(kase, "closed")

    # Reopen → re-resolve so it's closable again; a brand-new request is required.
    kase.transition_to!(:reopened)
    kase.transition_to!(:resolved)
    fresh = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))
    assert fresh.status_pending?
    assert_not_equal req.id, fresh.id, "the second closure needs its own sign-off, not the spent one"
  end
end
