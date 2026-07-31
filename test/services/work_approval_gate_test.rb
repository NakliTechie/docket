require "test_helper"

class WorkApprovalGateTest < ActiveSupport::TestCase
  test "a guarded work move waits for a distinct checker and is consumed once" do
    item = work_items(:pep_one)
    target = workflow_states(:pep_done)
    process = ApprovalProcess.create!(name: "Done sign-off", trigger_type: :work_item_transition,
                                      trigger_key: "PEP:Done")

    refute item.guarded_transition_to(target, requested_by: users(:admin))
    refute item.reload.done?
    request = item.approval_requests.status_pending.find_by!(approval_process: process)
    assert_equal target.id.to_s, request.requested_action

    assert_raises(ApprovalGate::Error) do
      ApprovalGate.approve!(request, approver: users(:admin), reason: "Self review")
    end
    ApprovalGate.approve!(request, approver: users(:client_admin),
                          reason: "Acceptance criteria verified.")

    assert item.reload.done?
    assert request.reload.status_approved?
    assert request.consumed_at?
  end
end
