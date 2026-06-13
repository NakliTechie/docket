# Decisioning controls: run the rule engine (persist + auto-apply autonomous),
# and approve/reject the parked confirm/of_record proposals. Admin/supervisor
# only (DecisionPolicy). All effects are audited via Decisioning::Dispatcher.
class DecisionsController < ApplicationController
  def run
    authorize :decision, policy_class: DecisionPolicy
    Decisioning::Dispatcher.run!
    redirect_to dashboard_path, notice: t(".ran")
  end

  def approve
    authorize :decision, policy_class: DecisionPolicy
    Decisioning::Dispatcher.approve!(Decision.find(params[:id]), approver: Current.user, reason: params[:reason])
    redirect_to dashboard_path, notice: t(".approved")
  rescue Decisioning::Error => e
    redirect_to dashboard_path, alert: e.message
  end

  def reject
    authorize :decision, policy_class: DecisionPolicy
    Decisioning::Dispatcher.reject!(Decision.find(params[:id]), approver: Current.user)
    redirect_to dashboard_path, notice: t(".rejected")
  rescue Decisioning::Error => e
    redirect_to dashboard_path, alert: e.message
  end
end
