module Decisioning
  # One proposed decision produced by a rule over the deployment's own data.
  # A decision is a *recommendation* carrying its accountability tier — it is
  # never auto-executed here. Acting on it routes through the existing gates
  # (Connectors::Invoke for external actions; the domain-action path for
  # internal ones), where decision_class decides whether a human is required.
  #
  #   :autonomous — computing the signal is reversible analysis; safe to surface.
  #   :confirm    — acting needs a human to confirm first.
  #   :of_record  — discretionary AND adverse: a human must give a reasoned order.
  Decision = Struct.new(
    :rule, :version, :subject_type, :subject_id, :subject_label,
    :signal, :recommendation, :effect, :decision_class, :reasoning,
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
