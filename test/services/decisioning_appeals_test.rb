require "test_helper"

# The appeal/contest workflow for decisions of record: file → overturn (reverse
# the decision) or deny (it stands), all through the Dispatcher gate.
class DecisioningAppealsTest < ActiveSupport::TestCase
  # An applied of_record decision that attached the "flagged" label to a case.
  def applied_of_record_decision
    kase = Case.create!(subject: "Adverse", contact: contacts(:asha))
    kase.add_label("flagged")
    Decision.create!(rule: "manual", version: "1", subject: kase, signal: "flagged",
                     decision_class: "of_record", status: :applied, action: "label")
  end

  test "only an applied decision of record can be appealed" do
    proposed = Decision.create!(rule: "r", version: "1", subject: contacts(:asha), signal: "x",
                                decision_class: "of_record", status: :proposed)
    assert_raises(Decisioning::Error) { Decisioning::Dispatcher.file_appeal!(proposed, grounds: "no") }

    autonomous = Decision.create!(rule: "r2", version: "1", subject: contacts(:asha), signal: "y",
                                  decision_class: "autonomous", status: :applied)
    assert_raises(Decisioning::Error) { Decisioning::Dispatcher.file_appeal!(autonomous, grounds: "no") }

    appeal = Decisioning::Dispatcher.file_appeal!(applied_of_record_decision, grounds: "wrong call")
    assert appeal.status_pending?
    assert_equal "wrong call", appeal.grounds
  end

  test "overturning reverses the decision and dismisses it; a reasoned order is required" do
    decision = applied_of_record_decision
    appeal = Decisioning::Dispatcher.file_appeal!(decision, grounds: "wrong")

    assert_raises(Decisioning::Error) do
      Decisioning::Dispatcher.overturn_appeal!(appeal, reviewer: users(:admin), reason: "  ")
    end

    Decisioning::Dispatcher.overturn_appeal!(appeal, reviewer: users(:admin), reason: "evidence shows an error")
    assert appeal.reload.status_overturned?
    assert_equal users(:admin), appeal.reviewed_by
    assert decision.reload.status_dismissed?, "the decision no longer stands"
    assert_not decision.subject.reload.label?("flagged"), "its label was reversed"
  end

  test "denying leaves the decision standing" do
    decision = applied_of_record_decision
    appeal = Decisioning::Dispatcher.file_appeal!(decision, grounds: "wrong")

    Decisioning::Dispatcher.deny_appeal!(appeal, reviewer: users(:admin), reason: "upheld on review")
    assert appeal.reload.status_denied?
    assert decision.reload.status_applied?, "the decision stands"
    assert decision.subject.reload.label?("flagged")
  end

  test "an appeal cannot be resolved twice" do
    appeal = Decisioning::Dispatcher.file_appeal!(applied_of_record_decision, grounds: "wrong")
    Decisioning::Dispatcher.deny_appeal!(appeal, reviewer: users(:admin))
    assert_raises(Decisioning::Error) do
      Decisioning::Dispatcher.overturn_appeal!(appeal, reviewer: users(:admin), reason: "x")
    end
  end
end
