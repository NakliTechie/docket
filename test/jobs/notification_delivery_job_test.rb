require "test_helper"

class NotificationDeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "configurable email sends once for the latest occurrence" do
    Setting.set("notification_email_enabled", true)
    notification = Notifications::Publish.call(
      recipient: users(:agent_a), kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "mail-once", title: "Assigned", body: "Please review",
      metadata: { reference: "DKT-TEST-3456", subject: "Garbage not collected" }
    )
    clear_enqueued_jobs

    assert_emails 1 do
      NotificationDeliveryJob.perform_now(notification.id)
      NotificationDeliveryJob.perform_now(notification.id)
    end
    assert_equal 1, notification.reload.email_delivery_count
    assert notification.emailed_at.present?
  ensure
    Setting.unset("notification_email_enabled")
  end

  test "read notifications are not mailed" do
    Setting.set("notification_email_enabled", true)
    notification = Notifications::Publish.call(
      recipient: users(:agent_a), kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "read-before-mail", title: "Assigned", body: "Please review"
    )
    notification.mark_read!

    assert_no_emails { NotificationDeliveryJob.perform_now(notification.id) }
  ensure
    Setting.unset("notification_email_enabled")
  end

  test "no SMTP records an unavailable outbox state instead of a false success" do
    Setting.set("notification_email_enabled", true)
    notification = Notifications::Publish.call(
      recipient: users(:agent_a), kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "mail-unavailable", title: "Assigned", body: "Please review"
    )
    original = Rails.application.config.x.outbound_mail_available
    Rails.application.config.x.outbound_mail_available = false

    assert_no_emails { NotificationDeliveryJob.perform_now(notification.id) }

    assert notification.reload.email_unavailable?
    assert_equal 0, notification.email_delivery_count
  ensure
    Rails.application.config.x.outbound_mail_available = original
    Setting.unset("notification_email_enabled")
  end
end
