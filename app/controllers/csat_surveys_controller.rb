class CsatSurveysController < ApplicationController
  require_feature "service_desk"
  allow_unauthenticated_access
  layout "public"

  before_action :set_survey

  def show; end

  def create
    @survey.respond!(score: response_params[:score], comment: response_params[:comment])
    render :thanks, status: :created
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_entity
  end

  private

  def set_survey
    @survey = CsatSurvey.find_signed!(params[:token], purpose: :csat)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    head :not_found
  end

  def response_params
    params.require(:csat_survey).permit(:score, :comment)
  end

  def skip_pundit? = true
end
