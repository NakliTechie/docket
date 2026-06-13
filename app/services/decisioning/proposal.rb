module Decisioning
  # One proposed decision produced by a rule over the deployment's own data — the
  # transient value object the engine emits. (The persisted, lifecycle-tracked
  # record the Dispatcher writes from it is the top-level `Decision` model.)
  # A proposal is a *recommendation* carrying its accountability tier:
  #
  #   :autonomous — computing the signal is reversible analysis; safe to apply.
  #   :confirm    — acting needs a human to confirm first.
  #   :of_record  — discretionary AND adverse: a human must give a reasoned order.
  Proposal = Struct.new(
    :rule, :version, :subject_type, :subject_id, :subject_label,
    :signal, :recommendation, :effect, :decision_class, :reasoning,
    :action, :action_params,
    keyword_init: true
  ) do
    def autonomous? = decision_class == :autonomous
    def requires_human? = decision_class != :autonomous

    # A stable provenance string for audit/logging: rule@version → subject.
    def provenance
      "#{rule}@#{version} #{subject_type}##{subject_id}"
    end
  end
end
