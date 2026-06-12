module Admin
  # The effector "exception lane": agent-initiated connector actions, where a
  # human-of-record approves or rejects the write/irreversible ones an agent
  # proposed. Reads execute without ever landing here.
  class ConnectorInvocationsController < ApplicationController
    before_action :set_invocation, only: %i[show approve reject]

    def index
      authorize ConnectorInvocation
      @invocations = policy_scope(ConnectorInvocation)
                       .includes(:connector, :requested_by)
                       .recent_first
      @invocations = @invocations.status_proposed if params[:filter] != "all"
    end

    def show
      authorize @invocation
    end

    def approve
      authorize @invocation, :approve?
      Connectors::Invoke.approve!(@invocation, approver: Current.user)
      if @invocation.reload.status_succeeded?
        redirect_to admin_connector_invocation_path(@invocation), notice: t(".approved")
      else
        redirect_to admin_connector_invocation_path(@invocation),
                    alert: t(".failed", error: @invocation.error)
      end
    rescue Connectors::Error => e
      redirect_to admin_connector_invocation_path(@invocation), alert: e.message
    end

    def reject
      authorize @invocation, :reject?
      Connectors::Invoke.reject!(@invocation, approver: Current.user)
      redirect_to admin_connector_invocation_path(@invocation), notice: t(".rejected")
    rescue Connectors::Error => e
      redirect_to admin_connector_invocation_path(@invocation), alert: e.message
    end

    private

    def set_invocation
      @invocation = ConnectorInvocation.find(params[:id])
    end
  end
end
