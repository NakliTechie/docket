class SequenceTrackingController < ActionController::Base
  TRANSPARENT_GIF = Base64.decode64("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==").freeze

  def open
    SequenceTracking.open!(params[:token])
    expires_now
    send_data TRANSPARENT_GIF, type: "image/gif", disposition: "inline"
  rescue SequenceTracking::InvalidToken
    head :not_found
  end

  def click
    destination = SequenceTracking.click!(params[:token], params[:destination])
    redirect_to destination, allow_other_host: true
  rescue SequenceTracking::InvalidToken
    head :not_found
  end
end
