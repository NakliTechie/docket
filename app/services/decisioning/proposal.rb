module Decisioning
  # One proposed decision produced by a rule over the deployment's own data — the
  # transient value object the engine emits. (The persisted, lifecycle-tracked
  # record the Dispatcher writes from it is the top-level `Decision` model.)
  # A proposal is a *recommendation* carrying its accountability tier:
  #
  #   :autonomous — computing the signal is reversible analysis; safe to apply.
  #   :confirm    — acting needs a human to confirm first.
  #   :of_record  — discretionary AND adverse: a human must give a reasoned order.
  # A plain value object: the Dispatcher reads decision_class straight off it and
  # the gating predicates live on the persisted Decision (Decision#autonomous?),
  # so the proposal carries no behaviour of its own. (The unused autonomous?/
  # requires_human?/provenance helpers were removed — S4.)
  Proposal = Struct.new(
    :rule, :version, :subject_type, :subject_id, :subject_label,
    :signal, :recommendation, :effect, :decision_class, :reasoning,
    :action, :action_params,
    keyword_init: true
  )
end
