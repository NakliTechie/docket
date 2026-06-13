module Decisioning
  module Rules
    # Open, not-yet-breached cases whose resolution deadline is imminent →
    # recommend prioritising/alerting. Acting (notifying, reassigning) is a
    # human-facing write → :confirm. (Already-overdue cases are breaches, not
    # at-risk — they're excluded.)
    class SlaAtRisk < Decisioning::Rule
      WINDOW = 4.hours

      def self.decision_class = :confirm
      def self.effect = :write

      def evaluate
        Case.open_cases
            .where(resolution_breached: false)
            .where(resolution_due_at: Time.current..(Time.current + WINDOW))
            .find_each.map do |kase|
          decision(
            subject: kase, label: kase.subject,
            signal: "sla_at_risk",
            recommendation: "Prioritise — resolution SLA due within #{(WINDOW / 1.hour).to_i}h.",
            reasoning: "resolution_due_at #{kase.resolution_due_at&.iso8601}; not yet breached"
          )
        end
      end
    end
  end
end
