require "test_helper"

class ScheduledCaseRoutingTest < ActiveSupport::TestCase
  test "applies a due rule exactly once per status episode" do
    rule = scheduled_rule(after_minutes: 60, then_priority: :urgent)
    kase = cases(:pension_case)
    kase.update_columns(status_changed_at: 2.hours.ago)

    assert_difference "RoutingRuleExecution.count", 1 do
      assert_equal 1, ScheduledCaseRouting.run!
    end
    assert kase.reload.priority_urgent?
    assert_equal rule.id, kase.routed_by_rule_id

    assert_no_difference "RoutingRuleExecution.count" do
      assert_equal 0, ScheduledCaseRouting.run!
    end
  end

  test "does not execute before wall-clock duration elapses" do
    scheduled_rule(after_minutes: 60, then_priority: :urgent)
    kase = cases(:pension_case)
    kase.update_columns(status_changed_at: 59.minutes.ago)

    assert_equal 0, ScheduledCaseRouting.run!
    refute kase.reload.priority_urgent?
  end

  test "business-time rules honor closed time" do
    calendar = BusinessCalendar.new(name: "Weekdays", time_zone: "UTC", is_default: true)
    (1..5).each do |weekday|
      calendar.business_calendar_windows.build(
        weekday: weekday, starts_minute: 540, ends_minute: 1020
      )
    end
    calendar.save!
    rule = scheduled_rule(after_minutes: 120, use_business_hours: true, then_priority: :urgent)
    kase = cases(:pension_case)
    kase.update_columns(status_changed_at: Time.utc(2026, 8, 3, 16, 30))

    refute ScheduledCaseRouting.execute!(
      rule, kase, at: Time.utc(2026, 8, 4, 10, 29), calendar: calendar
    )
    assert ScheduledCaseRouting.execute!(
      rule, kase, at: Time.utc(2026, 8, 4, 10, 30), calendar: calendar
    )
  end

  test "a later return to the same status creates a new episode" do
    rule = scheduled_rule(after_minutes: 1, then_priority: :urgent)
    kase = cases(:pension_case)
    first_episode = 2.hours.ago
    kase.update_columns(status_changed_at: first_episode)
    assert ScheduledCaseRouting.execute!(rule, kase, at: Time.current)

    second_run_at = Time.current
    kase.reload.update_columns(status_changed_at: second_run_at - 2.minutes,
                               priority: Case.priorities.fetch("normal"))
    kase.reload
    refute ScheduledCaseRouting.execution_exists?(rule, kase)
    assert_operator ScheduledCaseRouting.scheduled_for(rule, kase), :<=, second_run_at
    assert_difference "RoutingRuleExecution.count", 1 do
      assert ScheduledCaseRouting.execute!(rule, kase, at: second_run_at)
    end
    assert_equal 2, RoutingRuleExecution.where(routing_rule: rule, case: kase).count
  end

  private

  def scheduled_rule(after_minutes:, use_business_hours: false, **actions)
    RoutingRule.create!({
      name: "Escalate stale", trigger_type: :elapsed_time, if_status: :new,
      after_minutes: after_minutes, use_business_hours: use_business_hours
    }.merge(actions))
  end
end
