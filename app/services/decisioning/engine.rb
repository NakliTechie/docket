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
      Rules::StalledDeal
    ].freeze

    def run(rules: RULES)
      rules.flat_map { |klass| klass.new.evaluate }
    end

    # Counts grouped by accountability tier — the headline for the dashboard.
    def summary(decisions = run)
      counts = Hash.new(0)
      decisions.each { |d| counts[d.decision_class] += 1 }
      counts
    end
  end
end
