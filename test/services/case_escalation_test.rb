require "test_helper"

class CaseEscalationTest < ActiveSupport::TestCase
  # An elapsed-time rule on the "new" case (pension_case entered `new` an hour
  # ago), one level due 30 min in: reassign to sales + notify the supervisor.
  def elapsed_rule
    rule = EscalationRule.create!(name: "Aging new cases", trigger_type: :elapsed_time, if_status: "new")
    rule.escalation_levels.create!(position: 0, after_minutes: 30,
                                   then_assignee: users(:agent_a), notify_user: users(:supervisor))
    rule
  end

  test "fires a due elapsed-time level: reassigns the case and records an execution" do
    rule = elapsed_rule
    kase = cases(:pension_case)

    assert_difference "EscalationExecution.count", 1 do
      CaseEscalation.run!
    end
    assert_equal users(:agent_a), kase.reload.assignee
  end

  test "the notify-user receives an escalation notification" do
    rule = elapsed_rule
    kase = cases(:pension_case)
    CaseEscalation.run!
    assert users(:supervisor).notifications.kind_escalation.where(notifiable: kase).exists?
  end

  test "a not-yet-due level does not fire" do
    rule = EscalationRule.create!(name: "Later", trigger_type: :elapsed_time, if_status: "new")
    rule.escalation_levels.create!(position: 0, after_minutes: 600, then_assignee: users(:agent_a)) # 10h > 1h aged
    assert_no_difference "EscalationExecution.count" do
      CaseEscalation.run!
    end
  end

  test "idempotent: a second sweep does not re-fire the same level" do
    elapsed_rule
    CaseEscalation.run!
    assert_no_difference "EscalationExecution.count" do
      CaseEscalation.run!
    end
  end

  test "sla_breach trigger fires after the breached SLA's due time" do
    kase = cases(:assigned_case)
    kase.update_columns(resolution_due_at: 2.hours.ago, resolution_breached: true)
    rule = EscalationRule.create!(name: "Breach escalate", trigger_type: :sla_breach, breach_clock: "resolution")
    rule.escalation_levels.create!(position: 0, after_minutes: 30, then_assignee: users(:supervisor))

    CaseEscalation.run!
    assert_equal users(:supervisor), kase.reload.assignee
    assert EscalationExecution.where(case: kase).exists?
  end

  test "an inactive rule is skipped" do
    rule = elapsed_rule
    rule.update!(active: false)
    assert_no_difference "EscalationExecution.count" do
      CaseEscalation.run!
    end
  end

  test "does not fight elapsed-time routing rules — both can act on the same case" do
    # A routing rule and an escalation rule both target new cases; each keeps its
    # own execution ledger, so neither loops nor blocks the other.
    elapsed_rule # escalation reassigns to sales
    RoutingRule.create!(name: "Route new", trigger_type: "elapsed_time", if_status: "new",
                        after_minutes: 30, then_queue: queues(:pensions), then_assignment: "keep")

    assert_nothing_raised do
      CaseEscalation.run!
      ScheduledCaseRouting.run!
    end
    assert_equal users(:agent_a), cases(:pension_case).reload.assignee, "escalation's reassignment stands"
  end
end
