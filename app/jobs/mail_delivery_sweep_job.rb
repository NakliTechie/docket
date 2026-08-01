class MailDeliverySweepJob < ApplicationJob
  queue_as :default

  def perform
    each_active_tenant do
      CsatSurvey.delivery_attempting.where(delivery_claimed_at: ...1.hour.ago).find_each(&:recover_stale_delivery_claim!)
      CsatSurvey.delivery_pending.find_each(&:enqueue_delivery!)
      next unless Setting.get("notification_email_enabled", false)

      Notification.email_attempting.where(email_claimed_at: ...1.hour.ago).find_each(&:recover_stale_email_claim!)
      Notification.email_pending.find_each { |notification| NotificationDeliveryJob.perform_later(notification.id) }
    end
    record_sweep_success!
  end
end
