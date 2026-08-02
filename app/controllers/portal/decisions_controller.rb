module Portal
  # A signed-in customer can inspect and contest applied decisions of record
  # concerning themselves or one of their cases. Internal CRM decisions never
  # enter this scope.
  class DecisionsController < BaseController
    require_feature "decisioning"
    before_action :require_customer

    def index
      @decisions = visible_decisions
                   .where(decision_class: "of_record", status: %i[applied dismissed])
                   .includes(:appeals).recent_first
    end

    def appeal
      decision = visible_decisions.find(params[:id])
      Decisioning::Dispatcher.file_appeal!(
        decision, grounds: params[:grounds].to_s, appellant: current_contact
      )
      redirect_to portal_decisions_path, notice: t(".filed")
    rescue Decisioning::Error, ActiveRecord::RecordInvalid => error
      redirect_to portal_decisions_path, alert: error.message
    end

    private

    def visible_decisions
      Decision.concerning(current_contact)
    end
  end
end
