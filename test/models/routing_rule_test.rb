require "test_helper"

class RoutingRuleTest < ActiveSupport::TestCase
  def kase(**overrides)
    Case.new({ subject: "ATM ate my card", description: "at Karol Bagh", channel: :email,
               priority: :high, category: categories(:pension_delay), contact: contacts(:asha) }.merge(overrides))
  end

  test "needs at least one condition and one action" do
    refute RoutingRule.new(name: "empty").valid?
    refute RoutingRule.new(name: "cond only", if_priority: "high").valid?, "no action"
    refute RoutingRule.new(name: "act only", then_queue: queues(:pensions)).valid?, "no condition"
    assert RoutingRule.new(name: "ok", if_priority: "high", then_queue: queues(:pensions)).valid?
  end

  test "matches? — all set conditions must hold; blanks are any" do
    rule = RoutingRule.new(name: "r", if_channel: "email", if_priority: "high", then_queue: queues(:pensions))
    assert rule.matches?(kase)
    refute rule.matches?(kase(channel: :web_portal))
    refute rule.matches?(kase(priority: :low))
  end

  test "matches? on category and subject keyword" do
    rule = RoutingRule.new(name: "r", match_category: categories(:pension_delay),
                           if_subject_contains: "atm", then_priority: "urgent")
    assert rule.matches?(kase)
    refute rule.matches?(kase(category: nil))
    refute rule.matches?(kase(subject: "water bill"))
  end

  test "specific_user assignment requires an assignee; bad enum values rejected" do
    refute RoutingRule.new(name: "r", if_priority: "high", then_assignment: :specific_user).valid?
    assert RoutingRule.new(name: "r", if_priority: "high", then_assignment: :specific_user,
                           then_assignee: users(:agent_a)).valid?
    refute RoutingRule.new(name: "r", if_priority: "nonsense", then_queue: queues(:pensions)).valid?
  end
end
