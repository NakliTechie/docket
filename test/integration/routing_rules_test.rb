require "test_helper"

class RoutingRulesTest < ActionDispatch::IntegrationTest
  test "case_config managers can list, create, edit, and delete rules" do
    sign_in_as users(:client_admin)

    get routing_rules_path
    assert_response :success
    get new_routing_rule_path
    assert_response :success

    assert_difference "RoutingRule.count", 1 do
      post routing_rules_path, params: { routing_rule: {
        name: "ATM disputes", if_subject_contains: "atm", then_queue_id: queues(:pensions).id
      } }
    end
    rule = RoutingRule.order(:id).last
    assert_redirected_to routing_rules_path
    assert_equal "ATM disputes", rule.name
    assert_equal 0, rule.position, "the first rule appends at position 0"

    patch routing_rule_path(rule), params: { routing_rule: { then_priority: "urgent" } }
    assert_equal "urgent", rule.reload.then_priority

    delete routing_rule_path(rule)
    assert_not RoutingRule.exists?(rule.id)
  end

  test "new rules append in order and #move swaps a rule with its neighbour" do
    sign_in_as users(:client_admin)
    post routing_rules_path, params: { routing_rule: { name: "one", if_priority: "high", then_queue_id: queues(:pensions).id } }
    post routing_rules_path, params: { routing_rule: { name: "two", if_priority: "low", then_queue_id: queues(:sanitation).id } }
    one = RoutingRule.find_by!(name: "one")
    two = RoutingRule.find_by!(name: "two")
    assert one.position < two.position

    patch move_routing_rule_path(two, dir: "up")
    assert_redirected_to routing_rules_path
    assert two.reload.position < one.reload.position, "moving up swaps it ahead of its neighbour"
  end

  test "an invalid rule re-renders the form" do
    sign_in_as users(:client_admin)
    assert_no_difference "RoutingRule.count" do
      post routing_rules_path, params: { routing_rule: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "agents without routing:manage are forbidden" do
    sign_in_as users(:customer_service)
    get routing_rules_path
    assert_response :forbidden
    assert_no_difference "RoutingRule.count" do
      post routing_rules_path, params: { routing_rule: {
        name: "x", if_priority: "high", then_queue_id: queues(:pensions).id
      } }
    end
  end

  test "a manager can configure a business-time status rule" do
    sign_in_as users(:client_admin)

    assert_difference "RoutingRule.scheduled.count", 1 do
      post routing_rules_path, params: { routing_rule: {
        name: "Escalate stale work", trigger_type: "elapsed_time",
        if_status: "in_progress", after_minutes: "240", use_business_hours: "1",
        then_priority: "urgent"
      } }
    end

    rule = RoutingRule.order(:id).last
    assert rule.trigger_elapsed_time?
    assert rule.use_business_hours?
    assert_equal 240, rule.after_minutes
    assert_redirected_to routing_rules_path
  end

  test "deleting a used rule retains the routed case and execution history" do
    rule = RoutingRule.create!(
      name: "Used rule", if_priority: "normal", then_queue: queues(:pensions)
    )
    kase = Case.create!(subject: "Routed", contact: contacts(:asha), priority: :normal)
    assert_equal rule, kase.reload.routed_by_rule
    sign_in_as users(:client_admin)

    assert_difference "RoutingRule.count", -1 do
      delete routing_rule_path(rule)
    end
    assert Case.exists?(kase.id)
    assert_nil kase.reload.routed_by_rule_id
  end
end
