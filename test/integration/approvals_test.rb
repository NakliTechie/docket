require "test_helper"

# PG4 — the maker-checker surfaces end to end: the approval-rule CRUD, the
# checker's queue, and the guarded case-closure flow.
class ApprovalsTest < ActionDispatch::IntegrationTest
  def closure_process
    ApprovalProcess.create!(name: "Closure sign-off", trigger_type: :case_transition, trigger_key: "closed")
  end

  def resolved_case
    kase = Case.create!(subject: "Refund dispute", channel: :staff, contact: contacts(:asha))
    kase.transition_to!(:triaged)
    kase.transition_to!(:resolved)
    kase
  end

  # --- approval-rule CRUD (case_config:manage) ---

  test "a config manager can list, create, and delete approval rules" do
    sign_in_as users(:client_admin)
    get approval_processes_path
    assert_response :success

    assert_difference "ApprovalProcess.count", 1 do
      post approval_processes_path, params: { approval_process: {
        name: "Closure", trigger_type: "case_transition", trigger_key: "closed"
      } }
    end
    assert_redirected_to approval_processes_path

    process = ApprovalProcess.order(:id).last
    delete approval_process_path(process)
    assert_not ApprovalProcess.exists?(process.id)
  end

  test "an invalid trigger_key (not a status) re-renders the form" do
    sign_in_as users(:client_admin)
    assert_no_difference "ApprovalProcess.count" do
      post approval_processes_path, params: { approval_process: {
        name: "Bad", trigger_type: "case_transition", trigger_key: "nonsense"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "approval-rule CRUD is gated on case_config:manage" do
    sign_in_as users(:customer_service)
    get approval_processes_path
    assert_response :forbidden
  end

  # --- the guarded closure flow (maker → checker) ---

  test "a guarded closure is parked for approval, then an approver closes it" do
    closure_process
    kase = resolved_case

    sign_in_as users(:client_admin)
    assert_difference "ApprovalRequest.count", 1 do
      post transition_case_path(kase, status: "closed")
    end
    assert kase.reload.status_resolved?, "the case is parked, not closed"

    req = kase.approval_requests.status_pending.last
    post approve_admin_approval_request_path(req, reason: "Confirmed resolution with citizen.")
    assert kase.reload.status_closed?, "approval performs the guarded transition"
    assert req.reload.status_approved?
  end

  test "rejecting a parked closure leaves the case open" do
    closure_process
    kase = resolved_case
    req = ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))

    sign_in_as users(:client_admin)
    post reject_admin_approval_request_path(req, reason: "Citizen still disputes the outcome.")
    assert kase.reload.status_resolved?
    assert req.reload.status_rejected?
  end

  test "an unguarded transition still goes straight through" do
    kase = Case.create!(subject: "x", channel: :staff, contact: contacts(:asha))
    sign_in_as users(:client_admin)
    post transition_case_path(kase, status: "triaged")
    assert kase.reload.status_triaged?, "no process guards :triaged → normal transition"
  end

  # --- the checker queue (invocation:review) ---

  test "the approver queue lists pending requests for reviewers" do
    closure_process
    kase = resolved_case
    ApprovalGate.submit_transition!(kase, "closed", requested_by: users(:agent_a))

    sign_in_as users(:client_admin)
    get admin_approval_requests_path
    assert_response :success
    assert_select "td", text: /#{kase.tracking_id}/

    sign_in_as users(:customer_service)
    get admin_approval_requests_path
    assert_response :forbidden
  end
end
