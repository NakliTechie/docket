module Admin
  # PG5 — edit the tenant's lead-scoring scorecard (singleton). CRM configuration,
  # gated on pipeline:manage like lead routing.
  class LeadScorecardsController < ApplicationController
    require_feature "crm"

    def show
      @scorecard = LeadScorecard.current
      authorize @scorecard
    end

    def update
      @scorecard = LeadScorecard.current
      authorize @scorecard
      if @scorecard.update(scorecard_params)
        redirect_to admin_lead_scorecard_path, notice: t(".updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def scorecard_params
      params.require(:lead_scorecard).permit(
        *LeadScorecard::WEIGHTS, :warm_threshold, :hot_threshold, :warm_sources
      )
    end
  end
end
