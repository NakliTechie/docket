class CsatReport
  attr_reader :from, :to

  def initialize(from:, to:)
    @from = from
    @to = to
  end

  def as_json
    {
      from: from, to: to, invitations: invited.count, responses: responded.count,
      response_rate: percentage(responded.count, invited.count),
      average_score: average_score,
      score_distribution: (1..5).index_with { |score| responded.where(score: score).count }
    }
  end

  def comments
    responded.where.not(comment: [ nil, "" ]).includes(:case, :contact).order(responded_at: :desc)
  end

  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << %w[tracking_id score comment responded_at]
      comments.find_each do |survey|
        csv << [ survey.case.tracking_id, survey.score, csv_safe(survey.comment), survey.responded_at ]
      end
    end
  end

  private

  def invited
    @invited ||= CsatSurvey.where(invited_at: from.beginning_of_day..to.end_of_day)
  end

  def responded = invited.responded

  def average_score
    value = responded.average(:score)
    value&.to_f&.round(2)
  end

  def percentage(numerator, denominator)
    denominator.zero? ? nil : (numerator * 100.0 / denominator).round(1)
  end

  def csv_safe(value)
    value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
  end
end
