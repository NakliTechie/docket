module Admin
  # The appeal/contest queue for decisions of record: file a customer's appeal,
  # then overturn (reverse the decision) or deny it (the decision stands). All
  # invocation:review tier — the human-of-record over the deployment's decisions.
  class DecisionAppealsController < ApplicationController
    before_action :set_appeal, only: %i[overturn deny]

    def index
      authorize DecisionAppeal
      @appeals = policy_scope(DecisionAppeal).recent_first.includes(:decision, :appellant)
      @appealable = Decision.status_applied.where(decision_class: "of_record").recent_first
    end

    def create
      authorize DecisionAppeal
      decision = Decision.find(params[:decision_id])
      Decisioning::Dispatcher.file_appeal!(decision, grounds: params[:grounds].to_s)
      redirect_to admin_decision_appeals_path, notice: t(".filed")
    rescue Decisioning::Error, ActiveRecord::RecordInvalid => e
      redirect_to admin_decision_appeals_path, alert: e.message
    end

    def overturn
      authorize @appeal
      Decisioning::Dispatcher.overturn_appeal!(@appeal, reviewer: Current.user, reason: params[:reason].to_s)
      redirect_to admin_decision_appeals_path, notice: t(".overturned")
    rescue Decisioning::Error => e
      redirect_to admin_decision_appeals_path, alert: e.message
    end

    def deny
      authorize @appeal
      Decisioning::Dispatcher.deny_appeal!(@appeal, reviewer: Current.user, reason: params[:reason].presence)
      redirect_to admin_decision_appeals_path, notice: t(".denied")
    rescue Decisioning::Error => e
      redirect_to admin_decision_appeals_path, alert: e.message
    end

    private

    def set_appeal
      @appeal = DecisionAppeal.find(params[:id])
    end
  end
end
