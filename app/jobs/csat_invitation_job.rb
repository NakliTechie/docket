class CsatInvitationJob < ApplicationJob
  queue_as :mailers

  class DeliveryError < StandardError; end

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 6 do |job, error|
    survey = job.arguments.first
    survey&.mark_delivery_failed!(error.message)
  end

  def perform(survey)
    return unless survey&.claim_delivery!
    unless OutboundMail.available?
      survey.mark_delivery_unavailable!
      return
    end

    CsatMailer.invitation(survey).deliver_now
    survey.mark_delivery_delivered!
  rescue StandardError => e
    survey&.update_columns(delivery_status: CsatSurvey.delivery_statuses.fetch("pending"),
                           delivery_last_error: e.message.to_s.truncate(500), updated_at: Time.current)
    raise DeliveryError, e.message
  end
end
