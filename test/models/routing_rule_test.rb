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

  test "elapsed-time rules require a status and bounded positive duration" do
    rule = RoutingRule.new(
      name: "Escalate stale", trigger_type: :elapsed_time, if_status: :in_progress,
      after_minutes: 240, then_priority: :urgent
    )
    assert rule.valid?

    rule.if_status = nil
    refute rule.valid?
    rule.if_status = :in_progress
    rule.after_minutes = 0
    refute rule.valid?
  end

  test "creation rules reject hidden schedule settings" do
    rule = RoutingRule.new(
      name: "Mixed trigger", trigger_type: :case_created, if_status: :new,
      after_minutes: 60, then_priority: :urgent
    )

    refute rule.valid?
    assert_includes rule.errors[:base],
                    I18n.t("activerecord.errors.models.routing_rule.attributes.base.intake_has_schedule")
  end
end
