require "test_helper"

# The decisioning controls (run / approve / reject) — admin/supervisor only,
# same authority as the dashboard that surfaces them.
class DecisionsTest < ActionDispatch::IntegrationTest
  test "an admin can run decisioning and it persists proposals" do
    sign_in_as users(:admin)
    Lead.create!(name: "Hot", email: "h@x.com", phone: "+91990000001",
                 company_name: "Acme", source: :referral, status: :new)
    post run_decisions_path
    assert_redirected_to dashboard_path
    assert Decision.exists?(rule: "lead_score")
  end

  test "an ordinary agent cannot run decisioning" do
    sign_in_as users(:agent_a)
    post run_decisions_path
    assert_response :forbidden
  end

  test "an admin approves a parked decision, which applies it" do
    sign_in_as users(:admin)
    kase = Case.create!(subject: "x", contact: contacts(:asha))
    decision = Decision.create!(rule: "sla_at_risk", version: "1", subject: kase,
                                signal: "sla_at_risk", decision_class: "confirm", status: :proposed)
    post approve_decision_path(decision)
    assert_redirected_to dashboard_path
    assert decision.reload.status_applied?
    assert kase.reload.label?("sla_at_risk")
  end

  test "an anonymous visitor is bounced to sign in" do
    post run_decisions_path
    assert_redirected_to new_session_path
  end
end
