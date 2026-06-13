module Admin
  # The checker's queue (PG4): pending maker-checker requests, approved with a
  # reasoned order (which performs the guarded action) or rejected (it's
  # blocked). invocation:review tier — the human of record.
  class ApprovalRequestsController < ApplicationController
    before_action :set_request, only: %i[approve reject]

    def index
      authorize ApprovalRequest
      @pending = policy_scope(ApprovalRequest).status_pending.recent_first
                   .includes(:approval_process, :requested_by, :subject)
      @recent = policy_scope(ApprovalRequest).where.not(status: :pending).recent_first
                  .includes(:approval_process, :decided_by, :subject).limit(20)
    end

    def approve
      authorize @request
      ApprovalGate.approve!(@request, approver: Current.user, reason: params[:reason].to_s)
      redirect_to admin_approval_requests_path, notice: t(".approved")
    rescue ApprovalGate::Error, Case::InvalidTransition => e
      redirect_to admin_approval_requests_path, alert: e.message
    end

    def reject
      authorize @request
      ApprovalGate.reject!(@request, approver: Current.user, reason: params[:reason].presence)
      redirect_to admin_approval_requests_path, notice: t(".rejected")
    rescue ApprovalGate::Error => e
      redirect_to admin_approval_requests_path, alert: e.message
    end

    private

    def set_request
      @request = ApprovalRequest.find(params[:id])
    end
  end
end
