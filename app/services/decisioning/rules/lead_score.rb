module Decisioning
  module Rules
    # Rule-scorecard lead score: flags high-value open leads from cheap,
    # explainable signals. Computing the score is reversible analysis →
    # :autonomous (surfacing it doesn't act on the lead).
    class LeadScore < Decisioning::Rule
      THRESHOLD = 3
      MAX = 5
      WARM_SOURCES = %w[referral web_form].freeze

      def self.decision_class = :autonomous

      def evaluate
        Lead.where(status: %w[new working]).find_each.filter_map do |lead|
          score, matched = score_for(lead)
          next if score < THRESHOLD
          decision(
            subject: lead,
            signal: "high_value_lead",
            recommendation: "Prioritise for follow-up (lead score #{score}/#{MAX}).",
            reasoning: "score #{score}/#{MAX}; matched: #{matched.join(', ')}"
          )
        end
      end

      private

      def score_for(lead)
        matched = []
        matched << "email" if lead.email.present?
        matched << "phone" if lead.phone.present?
        matched << "company" if lead.company_name.present?
        matched << "warm_source" if WARM_SOURCES.include?(lead.source)
        matched << "owned" if lead.owner_id.present?
        [ matched.size, matched ]
      end
    end
  end
end
