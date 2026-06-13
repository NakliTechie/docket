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
          decision_class: proposal.decision_class.to_s, reasoning: proposal.reasoning,
          action: (proposal.action.presence || "label"), action_params: proposal.action_params
        )
        decision
      rescue ActiveRecord::RecordNotUnique
        # Lost the upsert race with a concurrent run! — return the row the other
        # run created instead of a duplicate / 500 (M3).
        Decision.find_by(rule: proposal.rule, subject_type: proposal.subject_type, subject_id: proposal.subject_id)
      end
    end

    # Perform the decision's action on its subject and mark it applied. The
    # action gates by decision_class upstream (autonomous auto-applies; confirm/
    # of_record reach here only after approve!), so a richer action — routing a
    # case, enrolling a lead — rides the same accountability path as a label.
    def apply!(decision)
      perform_action!(decision)
      decision.update!(status: :applied, decided_at: Time.current)
      decision
    end

    # Best-effort reversal of an applied decision's effect (used by the appeal
    # overturn path). Labels and enrollments reverse cleanly; a re-route restores
    # the queue captured at apply time (M6).
    def reverse!(decision)
      subject = decision.subject
      case decision.action
      when "enroll_lead"
        sequence_id = decision.action_params&.dig("sequence_id")
        SequenceEnrollment.where(enrollable: subject, sequence_id: sequence_id)
                          .find_each { |e| e.update!(status: :cancelled) }
      when "route_case"
        if subject.respond_to?(:queue_id=) && decision.action_params&.key?("previous_queue_id")
          subject.update!(queue_id: decision.action_params["previous_queue_id"])
        end
      else subject&.try(:remove_label, decision.signal)
      end
      decision
    end

    def perform_action!(decision)
      subject = decision.subject
      case decision.action
      when "route_case"
        queue_id = decision.action_params&.dig("queue_id")
        if queue_id && subject.respond_to?(:queue_id=)
          # Capture the prior queue so an overturned appeal can restore it (M6).
          decision.update_column(:action_params, (decision.action_params || {}).merge("previous_queue_id" => subject.queue_id))
          subject.update!(queue_id: queue_id)
        end
      when "enroll_lead"
        sequence = Sequence.find_by(id: decision.action_params&.dig("sequence_id"))
        if sequence && subject && !SequenceEnrollment.exists?(sequence: sequence, enrollable: subject)
          sequence.enroll!(subject)
        end
      else # "label" — attach the reversible segment tag (the default)
        subject&.try(:add_label, decision.signal)
      end
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

    # ── Appeal / contest path (for decisions of record) ─────────────────────
    # File a contest against an applied decision of record. The grounds are the
    # appellant's case; appellant is the contesting customer (optional — staff
    # may record it on their behalf).
    def file_appeal!(decision, grounds:, appellant: nil)
      raise Decisioning::Error, "only an applied decision of record can be appealed" unless decision.appealable?
      decision.appeals.create!(grounds: grounds, appellant: appellant)
    end

    # Overturn (grant) an appeal: reverse the decision's effect and dismiss it.
    # Like a decision of record itself, an overturn is a reasoned order.
    def overturn_appeal!(appeal, reviewer:, reason:)
      raise Decisioning::Error, "appeal is already resolved" unless appeal.status_pending?
      raise Decisioning::Error, "overturning requires a reasoned order" if reason.to_s.strip.blank?

      reverse!(appeal.decision)
      appeal.decision.update!(status: :dismissed)
      appeal.update!(status: :overturned, reviewed_by: reviewer, resolution: reason, resolved_at: Time.current)
      appeal
    end

    # Deny an appeal: the decision stands.
    def deny_appeal!(appeal, reviewer:, reason: nil)
      raise Decisioning::Error, "appeal is already resolved" unless appeal.status_pending?
      appeal.update!(status: :denied, reviewed_by: reviewer, resolution: reason.presence, resolved_at: Time.current)
      appeal
    end
  end
end
