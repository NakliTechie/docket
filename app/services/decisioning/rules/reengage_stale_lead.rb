module Decisioning
  module Rules
    # A lead still in :new past a dwell threshold → propose enrolling it in the
    # operator's re-engagement sequence (a richer action than a label). Reaching
    # out to a person is discretionary, so acting waits for a human (:confirm) —
    # routed through the same Dispatcher gate as everything else. Inert unless an
    # active sequence exists, so it never fires on a deployment that hasn't set
    # one up.
    class ReengageStaleLead < Decisioning::Rule
      DWELL_LIMIT = 7.days

      def self.decision_class = :confirm
      def self.effect = :write

      def evaluate
        sequence = Sequence.active.order(:id).first
        return [] unless sequence

        Lead.where(status: :new).where(leads: { created_at: ..DWELL_LIMIT.ago }).find_each.filter_map do |lead|
          next if SequenceEnrollment.exists?(enrollable: lead, sequence: sequence)

          decision(
            subject: lead,
            signal: "reengage_lead",
            recommendation: "Enroll in “#{sequence.name}” — new and untouched for #{(DWELL_LIMIT / 1.day).to_i}+ days.",
            reasoning: "status=new, age ≥ #{(DWELL_LIMIT / 1.day).to_i}d, not yet enrolled in #{sequence.name}",
            action: :enroll_lead,
            action_params: { "sequence_id" => sequence.id }
          )
        end
      end
    end
  end
end
