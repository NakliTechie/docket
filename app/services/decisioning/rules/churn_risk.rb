module Decisioning
  module Rules
    # A recent low CSAT response is an explainable retention-risk signal. The
    # label is reversible analysis; any retention outreach remains a separately
    # gated action.
    class ChurnRisk < Decisioning::Rule
      WINDOW = 90.days
      LOW_SCORE = 2

      def self.owner_feature = "service_desk"

      def evaluate
        responses = CsatSurvey.responded
                              .where(responded_at: WINDOW.ago.., score: ..LOW_SCORE)
                              .where.not(contact_id: nil)
        Contact.where(id: responses.select(:contact_id)).find_each.map do |contact|
          latest = responses.where(contact_id: contact.id).order(responded_at: :desc, id: :desc).first
          decision(
            subject: contact,
            signal: "churn_risk",
            recommendation: "Review retention after a recent low satisfaction response.",
            reasoning: "CSAT #{latest.score}/5 on case ##{latest.case_id} within #{WINDOW / 1.day} days"
          )
        end
      end
    end
  end
end
