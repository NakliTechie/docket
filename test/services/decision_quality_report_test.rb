require "test_helper"

class DecisionQualityReportTest < ActiveSupport::TestCase
  test "reports per-rule approval, rejection, and upheld-appeal rates" do
    subjects = 4.times.map do |index|
      Case.create!(subject: "Quality case #{index}", contact: contacts(:asha))
    end
    approved = create_decision(subject: subjects[0], status: :applied, approved_by: users(:decision_reviewer))
    overridden = create_decision(subject: subjects[1], rule: "quality_rule", signal: "overridden",
                                 status: :dismissed, approved_by: users(:decision_reviewer))
    DecisionAppeal.create!(decision: overridden, grounds: "Wrong basis", status: :overturned,
                           reviewed_by: users(:decision_reviewer), resolution: "Evidence changed",
                           resolved_at: Time.current)
    create_decision(subject: subjects[2], rule: "quality_rule", signal: "rejected", status: :rejected,
                    approved_by: users(:decision_reviewer))
    create_decision(subject: subjects[3], rule: "quality_rule", signal: "open", status: :proposed)

    row = DecisionQualityReport.new(from: Date.current, to: Date.current).rows.find do |candidate|
      candidate.rule == "quality_rule"
    end
    assert row
    assert_equal 1, row.proposed_count
    assert_equal 2, row.approved_count
    assert_equal 1, row.rejected_count
    assert_equal 1, row.overturned_count
    assert_equal 66.7, row.approval_rate
    assert_equal 33.3, row.rejection_rate
    assert_equal 50.0, row.override_rate
    assert approved.status_applied?
  end

  test "returns nil rates when no human review denominator exists" do
    create_decision(subject: cases(:pension_case), status: :proposed)
    row = DecisionQualityReport.new(from: Date.current, to: Date.current).rows.find do |candidate|
      candidate.rule == "quality_rule"
    end

    assert_nil row.approval_rate
    assert_nil row.rejection_rate
    assert_nil row.override_rate
  end

  test "excludes decisions created outside the selected cohort" do
    decision = create_decision(subject: cases(:pension_case), status: :rejected,
                               approved_by: users(:decision_reviewer))
    decision.update_columns(created_at: 10.days.ago)

    assert_empty DecisionQualityReport.new(from: 2.days.ago.to_date, to: Date.current).rows
  end

  private

  def create_decision(subject:, rule: "quality_rule", signal: SecureRandom.hex(4), status:,
                      approved_by: nil)
    Decision.create!(rule: rule, version: "1", subject: subject, signal: signal,
                     decision_class: "confirm", status: status, approved_by: approved_by,
                     decided_at: (Time.current unless status == :proposed))
  end
end
