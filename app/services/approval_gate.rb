# Maker-checker enforcement (PG4). Generalizes the decisioning reasoned-order
# pattern to configurable, case-level approvals:
#   • a guarded Case transition can't proceed until a checker approves it;
#   • an effector action covered by a process is escalated to human review.
# The maker submits a request; the checker approves (with a reasoned order →
# the action is performed) or rejects (it's blocked). Every step is audited.
module ApprovalGate
  Error = Class.new(StandardError)

  module_function

  # --- case transitions -------------------------------------------------------

  def guarded_transition?(_kase, to_status)
    ApprovalProcess.for_transition(to_status).present?
  end

  # Already approved (so the guarded transition may proceed)? True when nothing
  # guards it.
  def transition_cleared?(kase, to_status)
    process = ApprovalProcess.for_transition(to_status)
    return true unless process
    kase.approval_requests.status_approved
        .exists?(approval_process_id: process.id, requested_action: to_status.to_s)
  end

  # Maker submits the guarded transition for review — idempotent on the open
  # pending request for this (case, transition).
  def submit_transition!(kase, to_status, requested_by:)
    process = ApprovalProcess.for_transition(to_status)
    return nil unless process

    kase.approval_requests.status_pending
        .find_or_create_by!(approval_process: process, requested_action: to_status.to_s) do |req|
      req.requested_by = requested_by
    end
  end

  def pending_transition(kase, to_status)
    process = ApprovalProcess.for_transition(to_status)
    return nil unless process
    kase.approval_requests.status_pending
        .find_by(approval_process_id: process.id, requested_action: to_status.to_s)
  end

  # --- effector actions -------------------------------------------------------

  # Should this connector action be forced to human review (overriding the
  # connector's auto-approve)? Used by Connectors::Invoke#gated_status.
  def requires_action_review?(action_key)
    ApprovalProcess.for_action(action_key).present?
  end

  # --- decisions --------------------------------------------------------------

  # Checker approves: a reasoned order is mandatory (a blank rubber-stamp is
  # void), then the guarded action is performed under the approver's name.
  def approve!(request, approver:, reason:)
    raise Error, "request is not pending" unless request.status_pending?
    raise Error, "a reasoned order is required to approve" if reason.to_s.strip.blank?

    ApprovalRequest.transaction do
      request.update!(status: :approved, decided_by: approver, reason: reason, decided_at: Time.current)
      perform!(request, approver)
    end
    request
  end

  # Checker rejects: the guarded action is blocked; the case stays put.
  def reject!(request, approver:, reason: nil)
    raise Error, "request is not pending" unless request.status_pending?
    request.update!(status: :rejected, decided_by: approver, reason: reason.presence, decided_at: Time.current)
    request
  end

  # Carry out the now-authorized action. Attributed to the approver so the
  # reasoned order owns the transition in the audit chain.
  def perform!(request, approver)
    case request.approval_process.trigger_type
    when "case_transition"
      Current.set(actor: approver) { request.subject.transition_to!(request.requested_action) }
    end
  end
end
