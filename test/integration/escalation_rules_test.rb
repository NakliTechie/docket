require "test_helper"

class EscalationRulesTest < ActionDispatch::IntegrationTest
  test "case_config managers can list, create with tiers, edit, and delete" do
    sign_in_as users(:client_admin)

    get escalation_rules_path
    assert_response :success
    get new_escalation_rule_path
    assert_response :success

    assert_difference "EscalationRule.count", 1 do
      post escalation_rules_path, params: { escalation_rule: {
        name: "Breach escalate", trigger_type: "sla_breach", breach_clock: "resolution",
        escalation_levels_attributes: {
          "0" => { after_minutes: 30, then_assignee_id: users(:agent_a).id, notify_user_id: users(:supervisor).id },
          "1" => { after_minutes: "", then_assignee_id: "", notify_user_id: "" } # blank slot → dropped
        }
      } }
    end
    rule = EscalationRule.order(:id).last
    assert_redirected_to escalation_rules_path
    assert_equal 1, rule.escalation_levels.size, "the blank tier slot is dropped by reject_if"
    assert_equal 30, rule.escalation_levels.first.after_minutes

    get edit_escalation_rule_path(rule)
    assert_response :success

    delete escalation_rule_path(rule)
    assert_not EscalationRule.exists?(rule.id)
  end

  test "elapsed_time without a status re-renders the form" do
    sign_in_as users(:client_admin)
    assert_no_difference "EscalationRule.count" do
      post escalation_rules_path, params: { escalation_rule: {
        name: "Bad", trigger_type: "elapsed_time", if_status: "",
        escalation_levels_attributes: { "0" => { after_minutes: 30, notify_user_id: users(:supervisor).id } }
      } }
    end
    assert_response :unprocessable_entity
  end

  test "a user without case_config:manage is forbidden" do
    sign_in_as users(:sales)
    get escalation_rules_path
    assert_response :forbidden
  end
end
