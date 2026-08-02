module Decisioning
  module Rules
    # An open breached case marks the customer relationship at risk. This is a
    # reversible segment only; it does not reprioritise or contact anyone.
    class AtRiskContact < Decisioning::Rule
      def self.owner_feature = "service_desk"

      def evaluate
        breached = Case.open_cases.where(resolution_breached: true)
        Contact.where(id: breached.select(:contact_id)).find_each.map do |contact|
          count = breached.where(contact_id: contact.id).count
          decision(
            subject: contact,
            signal: "at_risk_contact",
            recommendation: "Review #{count} open case#{'s' unless count == 1} with a breached resolution SLA.",
            reasoning: "#{count} open resolution-breached case#{'s' unless count == 1}"
          )
        end
      end
    end
  end
end
