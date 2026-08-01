require "test_helper"

class EscalationRuleTest < ActiveSupport::TestCase
  test "name is required" do
    refute EscalationRule.new(trigger_type: :sla_breach).valid?
  end

  test "elapsed_time requires a status" do
    rule = EscalationRule.new(name: "R", trigger_type: :elapsed_time)
    refute rule.valid?
    assert rule.errors[:if_status].present?
  end

  test "breach_clock must be a known clock for sla_breach" do
    refute EscalationRule.new(name: "R", trigger_type: :sla_breach, breach_clock: "bogus").valid?
    assert EscalationRule.new(name: "R", trigger_type: :sla_breach, breach_clock: "first_response").valid?
  end

  test "if_priority must be a real Case priority" do
    refute EscalationRule.new(name: "R", trigger_type: :sla_breach, if_priority: "nope").valid?
  end

  test "matches? for sla_breach needs the breach flag and an open case" do
    rule = EscalationRule.new(name: "R", trigger_type: :sla_breach, breach_clock: "resolution")
    kase = cases(:assigned_case)
    kase.update_columns(resolution_breached: false)
    refute rule.matches?(kase.reload)
    kase.update_columns(resolution_breached: true)
    assert rule.matches?(kase.reload)
  end

  test "matches? for elapsed_time needs the configured status" do
    rule = EscalationRule.new(name: "R", trigger_type: :elapsed_time, if_status: "new")
    assert rule.matches?(cases(:pension_case)) # status new
    refute rule.matches?(cases(:assigned_case)) # status in_progress
  end

  test "a level needs at least one action and a positive delay" do
    rule = EscalationRule.create!(name: "R", trigger_type: :sla_breach, breach_clock: "resolution")
    refute rule.escalation_levels.build(after_minutes: 30).valid?, "no action is invalid"
    refute rule.escalation_levels.build(after_minutes: 0, notify_user: users(:supervisor)).valid?, "delay must be positive"
    assert rule.escalation_levels.build(after_minutes: 30, notify_user: users(:supervisor)).valid?
  end

  test "reference_at: breach due time vs status-entry time" do
    kase = cases(:assigned_case)
    kase.update_columns(resolution_due_at: 3.hours.ago, status_changed_at: 2.hours.ago)
    breach = EscalationRule.new(trigger_type: :sla_breach, breach_clock: "resolution")
    elapsed = EscalationRule.new(trigger_type: :elapsed_time, if_status: "in_progress")
    assert_equal kase.resolution_due_at, breach.reference_at(kase)
    assert_equal kase.status_changed_at, elapsed.reference_at(kase)
  end
end
