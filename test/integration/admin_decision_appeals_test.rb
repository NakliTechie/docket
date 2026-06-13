require "test_helper"

class AdminDecisionAppealsTest < ActionDispatch::IntegrationTest
  def applied_of_record(subject)
    Decision.create!(rule: "manual", version: "1", subject: subject, signal: "flagged",
                     decision_class: "of_record", status: :applied)
  end

  test "the invocation:review tier files, overturns, and views appeals" do
    sign_in_as users(:client_admin) # holds invocation:review
    decision = applied_of_record(contacts(:asha))

    assert_difference "DecisionAppeal.count", 1 do
      post admin_decision_appeals_path, params: { decision_id: decision.id, grounds: "mistaken call" }
    end
    appeal = DecisionAppeal.order(:id).last

    post overturn_admin_decision_appeal_path(appeal), params: { reason: "evidence shows an error" }
    assert appeal.reload.status_overturned?
    assert decision.reload.status_dismissed?

    get admin_decision_appeals_path
    assert_response :success
  end

  test "non-reviewers cannot reach the appeals queue" do
    sign_in_as users(:sales)
    get admin_decision_appeals_path
    assert_response :forbidden
  end
end
