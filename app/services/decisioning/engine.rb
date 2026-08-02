module Decisioning
  # Runs the registered rules over the deployment's own data and returns their
  # proposed Decisions. Pure read/analysis — no side effects, nothing persisted.
  # Surfacing decisions is :autonomous; acting on them gates by decision_class
  # through the existing effector/domain-action paths.
  module Engine
    module_function

    RULES = [
      Rules::LeadScore,
      Rules::SlaAtRisk,
      Rules::StalledDeal,
      Rules::ReengageStaleLead,
      Rules::RoutingSuggestion,
      Rules::ConversationReply,
      Rules::ChurnRisk,
      Rules::AtRiskContact,
      Rules::VipContact
    ].freeze

    def run(rules: RULES)
      rules.select { |klass| klass.owner_feature.nil? || Features.enabled?(klass.owner_feature) }
           .flat_map { |klass| klass.new.evaluate }
    end

    def owner_feature(rule_key)
      RULES.find { |klass| klass.key == rule_key.to_s }&.owner_feature
    end

    # Counts grouped by accountability tier — the headline for the dashboard.
    def summary(decisions = run)
      counts = Hash.new(0)
      decisions.each { |d| counts[d.decision_class] += 1 }
      counts
    end
  end
end
