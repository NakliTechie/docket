# Deliverable lifecycle transitions (Prithvi e2e, Phase 1), each attributed to
# the acting user so the hash-chained audit names who did it. The review→approve
# step is maker-checker: a DISTINCT human must approve, with a reasoned order —
# reusing ApprovalGate's distinct-human rule so segregation of duties is one
# implementation, not two. Always on (a deliverable can't be approved by its own
# author), fitting the regulated/AS9100 context deliverables live in.
module Deliverables
  Error = Deliverable::Error

  module_function

  # draft → in_review. Needs a scope to review.
  def submit_for_review!(deliverable, by:)
    ensure_status!(deliverable, "draft", "only a draft deliverable can be submitted for review")
    raise Error, "a deliverable needs at least one scope entry before review" if deliverable.scope_entries.empty?

    Current.set(actor: by) do
      deliverable.update!(status: :in_review, submitted_by: human(by))
    end
    deliverable
  end

  # in_review → approved. Distinct human + reasoned order (maker-checker).
  def approve!(deliverable, by:, reason:)
    ensure_status!(deliverable, "in_review", "only a deliverable in review can be approved")
    ensure_distinct_human!(deliverable.submitted_by, by)
    raise Error, "a reasoned order is required to approve" if reason.to_s.strip.blank?

    Current.set(actor: by) do
      deliverable.update!(status: :approved, approved_by: human(by), approval_reason: reason)
    end
    deliverable
  end

  # in_review → draft (rework). Clears the maker so a fresh submit is required.
  def return_to_draft!(deliverable, by:)
    ensure_status!(deliverable, "in_review", "only a deliverable in review can be returned to draft")

    Current.set(actor: by) do
      deliverable.update!(status: :draft, submitted_by: nil)
    end
    deliverable
  end

  # approved → issued. Freezes the content and stamps issued_at; the quote now
  # derives its lines from this exact scope.
  def issue!(deliverable, by:)
    ensure_status!(deliverable, "approved", "only an approved deliverable can be issued")
    raise Error, "an issued deliverable needs a scope" if deliverable.scope_entries.empty?

    Current.set(actor: by) do
      deliverable.update!(status: :issued, issued_at: Time.current)
    end
    deliverable
  end

  def ensure_status!(deliverable, expected, message)
    raise Error, message unless deliverable.status.to_s == expected.to_s
  end

  # Reuse ApprovalGate's rule, re-raising under this module's error type so
  # callers catch one thing.
  def ensure_distinct_human!(maker, checker)
    ApprovalGate.ensure_distinct_human!(maker, checker)
  rescue ApprovalGate::Error => error
    raise Error, error.message
  end

  def human(actor)
    actor if actor.is_a?(User)
  end
end
