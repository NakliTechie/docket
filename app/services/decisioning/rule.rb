module Decisioning
  # Base for a decisioning rule: a small, declarative, *versioned* unit that
  # evaluates the deployment's own data and emits proposed Decisions. Rules
  # compute signals (analysis) — they never take side effects. Subclasses set
  # the accountability tier (decision_class) their *recommended action* would
  # carry and implement #evaluate.
  #
  #   class HighValueLead < Rule
  #     def self.decision_class = :autonomous
  #     def evaluate
  #       Lead.where(...).map { |l| decision(subject: l, signal: "...", ...) }
  #     end
  #   end
  class Rule
    class << self
      def key = name.demodulize.underscore
      def version = "1"
      def decision_class = :autonomous
      # Descriptive audit metadata only — gating is on decision_class, never
      # effect (S8). Recorded on the Decision for the accountability trail.
      def effect = :read
    end

    # → Array<Proposal>. Override in subclasses.
    def evaluate
      raise NotImplementedError, "#{self.class} must implement #evaluate"
    end

    private

    # action defaults to :label (attach the reversible segment tag). A rule may
    # instead propose a richer action — :route_case, :enroll_lead — with its
    # target in action_params; the Dispatcher applies it through the same gate.
    def decision(subject:, signal:, recommendation:, reasoning:, label: nil,
                 action: :label, action_params: nil)
      Proposal.new(
        rule: self.class.key, version: self.class.version,
        subject_type: subject.class.name, subject_id: subject.id,
        subject_label: label || default_label(subject),
        signal: signal, recommendation: recommendation,
        effect: self.class.effect, decision_class: self.class.decision_class, reasoning: reasoning,
        action: action.to_s, action_params: action_params
      )
    end

    def default_label(subject)
      subject.try(:name).presence || subject.try(:subject).presence || "#{subject.class.name} ##{subject.id}"
    end
  end
end
