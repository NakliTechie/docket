module Decisioning
  # The domain-action gate for decisioning — the internal analogue of
  # Connectors::Invoke. It persists rule proposals, then routes each by its
  # accountability tier:
  #   :autonomous — applies immediately (reversible label, analysis-driven).
  #   :confirm    — parks as proposed until a human approves.
  #   :of_record  — parks; approval requires a reasoned order, never auto-applies.
  # Applying a decision attaches its segment label to the subject and marks the
  # decision applied — both audited.
  module Dispatcher
    module_function

    # Run the engine, persist proposals, and auto-apply the autonomous ones.
    # Returns the persisted Decision records.
    def run!
      decisions = persist(Engine.run)
      decisions.select { |d| d.status_proposed? && d.autonomous? }.each { |d| apply!(d) }
      decisions
    end

    # Upsert proposals into the Decision table, one row per (rule, subject). A
    # terminal decision (applied/rejected/dismissed) is left as-is — a rule
    # doesn't re-propose what's already been decided.
    def persist(proposals)
      proposals.filter_map do |proposal|
        decision = Decision.find_or_initialize_by(
          rule: proposal.rule, subject_type: proposal.subject_type, subject_id: proposal.subject_id
        )
        next decision unless decision.new_record? || decision.status_proposed?

        decision.update!(
          version: proposal.version, subject_label: proposal.subject_label, signal: proposal.signal,
          recommendation: proposal.recommendation, effect: proposal.effect.to_s,
          decision_class: proposal.decision_class.to_s, reasoning: proposal.reasoning
        )
        decision
      end
    end

    # Attach the decision's label to its subject and mark it applied.
    def apply!(decision)
      decision.subject&.try(:add_label, decision.signal)
      decision.update!(status: :applied, decided_at: Time.current)
      decision
    end

    # Human path for confirm / of_record: an approver releases a parked decision.
    # A decision of record needs a reasoned order (a blank rubber-stamp is void).
    def approve!(decision, approver:, reason: nil)
      raise Decisioning::Error, "decision is not awaiting confirmation" unless decision.status_proposed?
      if decision.of_record? && reason.to_s.strip.blank?
        raise Decisioning::Error, "a decision of record requires a reason (a reasoned order)"
      end
      decision.update!(approved_by: approver, decision_reason: reason.presence)
      apply!(decision)
    end

    def reject!(decision, approver:)
      raise Decisioning::Error, "decision is not awaiting confirmation" unless decision.status_proposed?
      decision.update!(status: :rejected, approved_by: approver, decided_at: Time.current)
      decision
    end
  end
end
