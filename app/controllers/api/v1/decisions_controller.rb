module Api
  module V1
    # REST parity for the decisioning review surface (the console
    # DecisionsController controls). Human-token-only by design: approving a
    # decision is an accountable, human-of-record action (maker-checker needs a
    # distinct human, and DecisionPolicy gates on decision:run, not an M2M
    # scope), so service-account bearers have no reach here.
    class DecisionsController < BaseController
      require_feature "decisioning"

      rescue_from Decisioning::Error do |e|
        render_error("decision_error", detail: e.message, status: :unprocessable_entity)
      end

      def index
        authorize_decision(:index?)
        pagy, records = pagy(filtered_decision_scope)
        render json: { data: records.map { |d| Serialize.decision(d) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize decision, :show?
        render json: { data: Serialize.decision(decision) }
      end

      def run
        authorize_decision(:run?)
        decisions = Decisioning::Dispatcher.run!
        render json: { data: decisions.map { |d| Serialize.decision(d) }, meta: { count: decisions.size } }
      end

      def approve
        authorize decision, :approve?
        Decisioning::Dispatcher.approve!(decision, approver: current_user, reason: params[:reason])
        render json: { data: Serialize.decision(decision.reload) }
      end

      def reject
        authorize decision, :reject?
        Decisioning::Dispatcher.reject!(decision, approver: current_user)
        render json: { data: Serialize.decision(decision.reload) }
      end

      private

      def decision
        @decision ||= Decision.find(params[:id])
      end

      def filtered_decision_scope
        scope = policy_scope(Decision).recent_first
        scope = scope.where(status: params[:status]) if Decision.statuses.key?(params[:status])
        scope = scope.where(decision_class: params[:decision_class]) if params[:decision_class].present?
        scope
      end

      # Human tokens only. A service account has no current_user, so it is denied
      # before Pundit even runs — an of-record approval demands a distinct human.
      def authorize_decision(query)
        raise ScopeDenied, "decisioning" unless current_user
        authorize(:decision, query, policy_class: DecisionPolicy)
      end
    end
  end
end
