# Per-rule feedback over decisions created in the selected cohort. Approval and
# rejection are mutually exclusive human-review outcomes. Override means an
# approved decision was later dismissed by an upheld appeal.
class DecisionQualityReport
  Row = Data.define(
    :rule, :proposed_count, :approved_count, :rejected_count, :overturned_count,
    :approval_rate, :rejection_rate, :override_rate
  )

  attr_reader :from, :to

  def initialize(from:, to:, decision_scope: Decision.all)
    @from = from.to_date
    @to = to.to_date
    @decision_scope = decision_scope
    raise ArgumentError, "from must be on or before to" if @from > @to
  end

  def rows
    @rows ||= decisions.group_by(&:rule).sort.map do |rule, grouped|
      approved = grouped.count { |decision| decision.approved_by_id? && (decision.status_applied? || decision.status_dismissed?) }
      rejected = grouped.count(&:status_rejected?)
      overturned = grouped.count { |decision| decision.appeals.any?(&:status_overturned?) }
      reviewed = approved + rejected

      Row.new(
        rule: rule,
        proposed_count: grouped.count(&:status_proposed?),
        approved_count: approved,
        rejected_count: rejected,
        overturned_count: overturned,
        approval_rate: percentage(approved, reviewed),
        rejection_rate: percentage(rejected, reviewed),
        override_rate: percentage(overturned, approved)
      )
    end
  end

  private

  def decisions
    @decision_scope.where(created_at: from.beginning_of_day..to.end_of_day).includes(:appeals).to_a
  end

  def percentage(numerator, denominator)
    return if denominator.zero?

    (numerator * 100.0 / denominator).round(1)
  end
end
