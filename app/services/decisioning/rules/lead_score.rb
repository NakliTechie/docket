module Decisioning
  module Rules
    # Rule-scorecard lead score: flags high-value open leads from cheap,
    # explainable signals. Computing the score is reversible analysis →
    # :autonomous (surfacing it doesn't act on the lead). The scorecard (weights,
    # thresholds, warm-sources) is tenant-editable (PG5); the shared LeadScoring
    # service is the single source of truth.
    class LeadScore < Decisioning::Rule
      def self.decision_class = :autonomous
      def self.owner_feature = "crm"

      def evaluate
        scorecard = LeadScorecard.current
        Lead.where(status: %w[new working]).find_each.filter_map do |lead|
          score = LeadScoring.score_for(lead, scorecard)
          next if score < scorecard.warm_threshold

          matched = LeadScoring.matched_signals(lead, scorecard)
          decision(
            subject: lead,
            signal: "high_value_lead",
            recommendation: "Prioritise for follow-up (lead score #{score}).",
            reasoning: "score #{score}; matched: #{matched.join(', ')}"
          )
        end
      end
    end
  end
end
