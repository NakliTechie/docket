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
      def effect = :read
    end

    # → Array<Decision>. Override in subclasses.
    def evaluate
      raise NotImplementedError, "#{self.class} must implement #evaluate"
    end

    private

    def decision(subject:, signal:, recommendation:, reasoning:, label: nil)
      Decision.new(
        rule: self.class.key, version: self.class.version,
        subject_type: subject.class.name, subject_id: subject.id,
        subject_label: label || default_label(subject),
        signal: signal, recommendation: recommendation,
        effect: self.class.effect, decision_class: self.class.decision_class, reasoning: reasoning
      )
    end

    def default_label(subject)
      subject.try(:name).presence || subject.try(:subject).presence || "#{subject.class.name} ##{subject.id}"
    end
  end
end
