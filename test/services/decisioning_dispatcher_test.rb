require "test_helper"

# The domain-action gate: Decisioning::Dispatcher persists rule proposals,
# auto-applies the autonomous ones (a reversible label on the subject), parks
# confirm/of_record for a human, and audits each transition.
class DecisioningDispatcherTest < ActiveSupport::TestCase
  setup do
    @lead = Lead.create!(name: "Hot", email: "h@x.com", phone: "+91990000001",
                         company_name: "Acme", source: :referral, status: :new) # scores high → autonomous
    @case = Case.create!(subject: "Due soon", contact: contacts(:asha))
    @case.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                         resolution_due_at: 2.hours.from_now) # at-risk → confirm
  end

  test "run! persists proposals, auto-applies autonomous, and parks confirm" do
    Decisioning::Dispatcher.run!

    lead_decision = Decision.find_by(rule: "lead_score", subject: @lead)
    assert lead_decision.status_applied?, "autonomous decision should auto-apply"
    assert @lead.reload.label?("high_value_lead"), "the reversible label should land on the subject"

    case_decision = Decision.find_by(rule: "sla_at_risk", subject: @case)
    assert case_decision.status_proposed?, "confirm decision should park for a human"
    assert_not @case.reload.label?("sla_at_risk"), "a parked decision must not act yet"
  end

  test "run! is idempotent — a re-run adds no duplicate decisions" do
    Decisioning::Dispatcher.run!
    assert_no_difference("Decision.count") { Decisioning::Dispatcher.run! }
  end

  test "approve! applies a parked confirm decision and records the approver" do
    Decisioning::Dispatcher.run!
    decision = Decision.find_by(rule: "sla_at_risk", subject: @case)
    Decisioning::Dispatcher.approve!(decision, approver: users(:admin))
    assert decision.reload.status_applied?
    assert @case.reload.label?("sla_at_risk")
    assert_equal users(:admin), decision.approved_by
  end

  test "reject! closes a parked decision without acting on the subject" do
    Decisioning::Dispatcher.run!
    decision = Decision.find_by(rule: "sla_at_risk", subject: @case)
    Decisioning::Dispatcher.reject!(decision, approver: users(:admin))
    assert decision.reload.status_rejected?
    assert_not @case.reload.label?("sla_at_risk")
  end

  test "an of_record decision needs a reasoned order before it applies" do
    decision = Decision.create!(rule: "manual", version: "1", subject: @case, signal: "x",
                                decision_class: "of_record", status: :proposed)
    assert_raises(Decisioning::Error) { Decisioning::Dispatcher.approve!(decision, approver: users(:admin)) }
    Decisioning::Dispatcher.approve!(decision, approver: users(:admin), reason: "reviewed and warranted")
    assert decision.reload.status_applied?
    assert_equal "reviewed and warranted", decision.decision_reason
  end

  test "approve! refuses a decision that is not awaiting confirmation" do
    decision = Decision.create!(rule: "manual", version: "1", subject: @lead, signal: "x",
                                decision_class: "confirm", status: :applied)
    assert_raises(Decisioning::Error) { Decisioning::Dispatcher.approve!(decision, approver: users(:admin)) }
  end

  test "labels are a reversible, deduped set" do
    @lead.add_label("vip")
    @lead.add_label("vip")
    assert_equal [ "vip" ], @lead.reload.labels
    @lead.remove_label("vip")
    assert_empty @lead.reload.labels
  end

  test "a duplicate decision per (tenant, rule, subject) is rejected by the unique index (M3)" do
    kase = Case.create!(subject: "Dup", contact: contacts(:asha))
    Decision.create!(rule: "dup_rule", version: "1", subject: kase, signal: "x",
                     decision_class: "autonomous", status: :proposed)
    assert_raises(ActiveRecord::RecordNotUnique) do
      Decision.create!(rule: "dup_rule", version: "1", subject: kase, signal: "y",
                       decision_class: "autonomous", status: :proposed)
    end
  end
end
