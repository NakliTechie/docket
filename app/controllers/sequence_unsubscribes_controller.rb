class SequenceUnsubscribesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :resolve_tenant
  skip_before_action :verify_authenticity_token, only: :create

  def show
    @resolution = SequenceUnsubscribe.resolve(params[:token])
  rescue SequenceUnsubscribe::InvalidToken
    head :not_found
  end

  def create
    @resolution = SequenceUnsubscribe.call(params[:token])
    render :success
  rescue SequenceUnsubscribe::InvalidToken
    head :not_found
  end

  private

  def skip_pundit?
    true
  end
end
