require "test_helper"

# Richer decisioning actions (beyond labels) ride the same decision_class gate:
# autonomous applies immediately, confirm/of_record only after approve!.
class DecisioningActionsTest < ActiveSupport::TestCase
  def active_sequence
    seq = Sequence.new(name: "Re-engage", active: true)
    seq.sequence_steps.build(position: 0, delay_days: 0, body: "Hi {{name}}")
    seq.save!
    seq
  end

  test "reengage_stale_lead proposes a confirm enrollment, applied only on approval" do
    seq = active_sequence
    lead = Lead.create!(name: "Cold Lead", email: "cold@example.com", status: :new)
    lead.update_columns(created_at: 10.days.ago)

    Decisioning::Dispatcher.run!
    decision = Decision.find_by(rule: "reengage_stale_lead", subject: lead)
    assert decision, "the rule proposed an enrollment decision"
    assert decision.status_proposed?, "confirm tier parks for a human"
    assert_equal "enroll_lead", decision.action
    assert_equal seq.id, decision.action_params["sequence_id"]
    assert_not SequenceEnrollment.exists?(enrollable: lead), "not enrolled until approved"

    Decisioning::Dispatcher.approve!(decision, approver: users(:admin))
    assert decision.reload.status_applied?
    assert SequenceEnrollment.exists?(enrollable: lead, sequence: seq),
           "approval enrolls the lead through the same gate"
  end

  test "a route_case action moves the case to the target queue when applied" do
    kase = Case.create!(subject: "Re-route me", contact: contacts(:asha), queue: queues(:pensions))
    target = queues(:sanitation)
    decision = Decision.create!(rule: "manual_route", version: "1", subject: kase, signal: "route",
                                decision_class: "autonomous", status: :proposed,
                                action: "route_case", action_params: { "queue_id" => target.id })
    Decisioning::Dispatcher.apply!(decision)
    assert_equal target, kase.reload.queue
  end

  test "reverse! cancels an enroll_lead decision's enrollment" do
    seq = active_sequence
    lead = Lead.create!(name: "Reversible", email: "rev@example.com", status: :new)
    decision = Decision.create!(rule: "manual_enroll", version: "1", subject: lead, signal: "enroll_lead",
                                decision_class: "confirm", status: :proposed,
                                action: "enroll_lead", action_params: { "sequence_id" => seq.id })
    Decisioning::Dispatcher.apply!(decision)
    assert SequenceEnrollment.exists?(enrollable: lead, sequence: seq)

    Decisioning::Dispatcher.reverse!(decision)
    assert SequenceEnrollment.where(enrollable: lead, sequence: seq).all?(&:status_cancelled?),
           "the enrollment is cancelled on reversal"
  end
end
