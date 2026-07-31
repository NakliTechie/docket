class NotificationDeliveryJob < ApplicationJob
  queue_as :default

  class DeliveryError < StandardError; end

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 6 do |job, error|
    notification = Notification.find_by(id: job.arguments.first)
    notification&.mark_email_failed!(error.message)
  end

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless Setting.get("notification_email_enabled", false)
    return unless notification&.claim_email_delivery!
    unless OutboundMail.available?
      notification.mark_email_unavailable!
      return
    end

    NotificationMailer.alert(notification).deliver_now
    notification.mark_email_delivered!
  rescue StandardError => e
    notification&.update_columns(email_status: Notification.email_statuses.fetch("pending"),
                                 email_last_error: e.message.to_s.truncate(500), updated_at: Time.current)
    raise DeliveryError, e.message
  end
end
