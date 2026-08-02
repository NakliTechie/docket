module Decisioning
  module Rules
    # Active direct or organisation-level SLA coverage is the deployment's
    # existing, currency-neutral signal for a priority customer relationship.
    class VipContact < Decisioning::Rule
      def self.owner_feature = "service_desk"

      def evaluate
        coverage = Entitlement.usable.covering(Time.current)
        direct = Contact.where(id: coverage.where.not(contact_id: nil).select(:contact_id))
        organisation = Contact.where(organisation_id: coverage.where.not(organisation_id: nil).select(:organisation_id))

        direct.or(organisation).find_each.map do |contact|
          policy = Entitlement.policy_for(contact)
          decision(
            subject: contact,
            signal: "vip_contact",
            recommendation: "Treat as a priority customer under active SLA coverage.",
            reasoning: "active entitlement resolves to SLA policy ##{policy.id}: #{policy.name}"
          )
        end
      end
    end
  end
end
