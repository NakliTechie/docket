class CrmMessageDeliveryJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = CrmMessage.find_by(id: message_id)
    return unless message

    unless message.tenant.feature?("crm")
      message.mark_skipped!("CRM is disabled for this tenant") if message.delivery_status_pending?
      return
    end

    return unless message.claim_delivery!

    unless OutboundMail.available?
      message.mark_skipped!("outbound email is not configured")
      return
    end

    CrmMailer.conversation_message(message).deliver_now
    message.mark_delivered!
  rescue StandardError => error
    message&.mark_failed!(error.message) if message&.delivery_status_attempting?
    Rails.logger.warn("[crm-message] delivery #{message_id} failed: #{error.message}")
  end
end
