module Decisioning
  module Rules
    # Re-evaluates imported or legacy open cases that never traversed the live
    # intake hook. It surfaces the first matching intake RoutingRule as a
    # proposal; a human must confirm before queue/category/priority/assignee
    # changes land.
    class RoutingSuggestion < Decisioning::Rule
      def self.decision_class = :confirm
      def self.effect = :write
      def self.owner_feature = "service_desk"

      def evaluate
        rules = RoutingRule.active.intake.ordered.to_a
        return [] if rules.empty?

        Case.open_cases.where(routed_by_rule_id: nil).find_each.filter_map do |kase|
          rule = rules.find { |candidate| candidate.matches?(kase) }
          next unless rule

          decision(
            subject: kase,
            signal: "routing_suggestion",
            recommendation: "Apply routing rule “#{rule.name}”.",
            reasoning: "first matching active intake rule ##{rule.id}: #{rule.name}",
            action: :apply_routing_rule,
            action_params: { "routing_rule_id" => rule.id }
          )
        end
      end
    end
  end
end
