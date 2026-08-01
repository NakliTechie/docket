# PG3 — advances open cases through their EscalationRule's ordered levels.
# For each active rule (position order), each matching case fires every level
# whose due time (reference + after_minutes) has passed and that hasn't fired
# yet for this reference episode. Firing reassigns the case (which notifies the
# new assignee via the existing case_assigned hook) and/or alerts a notify-user.
# Idempotent via EscalationExecution; runs as the system actor, fully audited.
module CaseEscalation
  module_function

  def run!(at: Time.current)
    EscalationRule.active.ordered.sum do |rule|
      rule.matching_cases.find_each.sum { |kase| advance!(rule, kase, at: at) }
    end
  end

  # Fire every due, not-yet-fired level for one case, in position order.
  def advance!(rule, kase, at:)
    reference = rule.reference_at(kase)
    return 0 if reference.nil?

    rule.escalation_levels.reduce(0) do |fired, level|
      due_at = reference + level.after_minutes.minutes
      next fired if due_at > at

      fired + (fire_level!(rule, level, kase, reference, at) ? 1 : 0)
    end
  end

  def fire_level!(rule, level, kase, reference, at)
    Case.transaction do
      kase = Case.lock.find(kase.id)
      return false unless rule.reload.active? && rule.matches?(kase)
      return false if already_fired?(level, kase, reference)

      reassign!(kase, level)
      Notifications::Events.case_escalated(kase, level.notify_user, level: level) if level.notify_user_id
      EscalationExecution.create!(escalation_level: level, case: kase, reference_at: reference, executed_at: at)
      true
    end
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def already_fired?(level, kase, reference)
    EscalationExecution.exists?(escalation_level_id: level.id, case_id: kase.id, reference_at: reference)
  end

  # Reassigning changes assignee_id, so Case's after_update_commit hook notifies
  # the new assignee — no separate assignment notification needed here. Only
  # assign to a valid case owner (mirrors CaseRouting); otherwise skip the
  # reassignment (a notify-user can still be alerted).
  def reassign!(kase, level)
    assignee = level.then_assignee
    return unless assignee&.case_assignee? && kase.assignee_id != assignee.id

    kase.update!(assignee: assignee)
  end
end
