module ScheduledCaseRouting
  TRACKED_ATTRIBUTES = %w[queue_id category_id priority assignee_id routed_by_rule_id].freeze

  module_function

  def run!(at: Time.current)
    calendar = BusinessCalendar.default
    RoutingRule.active.scheduled.ordered.sum do |rule|
      pending_cases(rule).find_each.count { |kase| execute!(rule, kase, at: at, calendar: calendar) }
    end
  end

  def execute!(rule, kase, at:, calendar: BusinessCalendar.default)
    Case.transaction do
      kase = Case.lock.find(kase.id)
      return false unless rule.reload.active? && rule.trigger_elapsed_time? && rule.matches?(kase)
      return false if execution_exists?(rule, kase)

      due_at = scheduled_for(rule, kase, calendar: calendar)
      return false if due_at > at

      before = kase.attributes.slice(*TRACKED_ATTRIBUTES)
      CaseRouting.apply_rule(kase, rule, complete_triage: false)
      after = kase.reload.attributes.slice(*TRACKED_ATTRIBUTES)
      RoutingRuleExecution.create!(
        routing_rule: rule, case: kase, rule_name: rule.name,
        case_status_changed_at: kase.status_changed_at,
        scheduled_for: due_at, executed_at: at,
        changes_summary: JSON.generate("before" => before, "after" => after)
      )
      true
    end
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def scheduled_for(rule, kase, calendar: BusinessCalendar.default)
    if rule.use_business_hours? && calendar
      BusinessTime.add_minutes(calendar: calendar, from: kase.status_changed_at,
                               minutes: rule.after_minutes)
    else
      kase.status_changed_at + rule.after_minutes.minutes
    end
  end

  def pending_cases(rule)
    cases = Case.arel_table
    executions = RoutingRuleExecution.arel_table
    join = cases.join(executions, Arel::Nodes::OuterJoin).on(
      executions[:case_id].eq(cases[:id])
        .and(executions[:routing_rule_id].eq(rule.id))
        .and(executions[:case_status_changed_at].eq(cases[:status_changed_at]))
    )

    Case.canonical.joins(join.join_sources)
        .where(status: rule.if_status)
        .where.not(status_changed_at: nil)
        .where(executions[:id].eq(nil))
        .order(:id)
  end

  def execution_exists?(rule, kase)
    RoutingRuleExecution.exists?(
      routing_rule: rule, case: kase, case_status_changed_at: kase.status_changed_at
    )
  end
end
