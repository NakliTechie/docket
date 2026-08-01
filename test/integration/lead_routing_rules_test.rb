require "test_helper"

class LeadRoutingRulesTest < ActionDispatch::IntegrationTest
  test "pipeline managers can list, create, edit, and delete rules" do
    sign_in_as users(:client_admin)

    get lead_routing_rules_path
    assert_response :success
    get new_lead_routing_rule_path
    assert_response :success

    assert_difference "LeadRoutingRule.count", 1 do
      post lead_routing_rules_path, params: { lead_routing_rule: {
        name: "Web leads", if_source: "web_form",
        then_assignment: "specific_user", then_owner_id: users(:sales).id
      } }
    end
    rule = LeadRoutingRule.order(:id).last
    assert_redirected_to lead_routing_rules_path
    assert_equal "Web leads", rule.name
    assert_equal 0, rule.position, "the first rule appends at position 0"

    patch lead_routing_rule_path(rule), params: { lead_routing_rule: { name: "Web-form leads" } }
    assert_equal "Web-form leads", rule.reload.name

    delete lead_routing_rule_path(rule)
    assert_not LeadRoutingRule.exists?(rule.id)
  end

  test "new rules append in order and #move swaps a rule with its neighbour" do
    sign_in_as users(:client_admin)
    post lead_routing_rules_path, params: { lead_routing_rule: { name: "one", if_source: "web_form", then_assignment: "round_robin" } }
    post lead_routing_rules_path, params: { lead_routing_rule: { name: "two", if_source: "referral", then_assignment: "round_robin" } }
    one = LeadRoutingRule.find_by!(name: "one")
    two = LeadRoutingRule.find_by!(name: "two")
    assert one.position < two.position

    patch move_lead_routing_rule_path(two, dir: "up")
    assert_redirected_to lead_routing_rules_path
    assert two.reload.position < one.reload.position, "moving up swaps it ahead of its neighbour"
  end

  test "an invalid rule re-renders the form" do
    sign_in_as users(:client_admin)
    assert_no_difference "LeadRoutingRule.count" do
      post lead_routing_rules_path, params: { lead_routing_rule: { name: "", then_assignment: "specific_user" } }
    end
    assert_response :unprocessable_entity
  end

  test "a user without pipeline:manage is forbidden" do
    sign_in_as users(:sales) # sales has lead:write but not pipeline:manage
    get lead_routing_rules_path
    assert_response :forbidden
  end
end
