require "test_helper"

class CrmMessageDeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "marks direct email unavailable when outbound mail is not configured" do
    original = Rails.application.config.x.outbound_mail_available
    Rails.application.config.x.outbound_mail_available = false
    message = CrmMessage.compose(
      subject: contacts(:asha), author: users(:sales), subject_line: "Hello", body: "Body"
    )

    perform_enqueued_jobs

    assert message.reload.delivery_status_skipped?
    assert_equal "outbound email is not configured", message.delivery_last_error
  ensure
    Rails.application.config.x.outbound_mail_available = original
  end

  test "mailer uses the record address for replies" do
    message = CrmMessage.create!(
      subject: contacts(:asha), author: users(:sales), channel: :email, direction: :outbound,
      delivery_status: :recorded, sender_email: users(:sales).email_address,
      recipient_email: contacts(:asha).email, subject_line: "Hello", body: "Body"
    )

    mail = CrmMailer.conversation_message(message)

    assert_equal [ contacts(:asha).email ], mail.to
    assert_equal [ CrmMailboxAddress.address_for(contacts(:asha)) ], mail.reply_to
    assert_equal "Body", mail.text_part.body.to_s.strip
  end

  test "a queued email is contained when CRM is disabled before delivery" do
    lead = Lead.create!(name: "Queued lead", email: "queued@example.test")
    message = CrmMessage.create!(
      subject: lead, author: users(:sales), body: "Do not send",
      subject_line: "Disabled module", recipient_email: lead.email,
      sender_email: users(:sales).email_address, delivery_status: :pending
    )
    ActsAsTenant.current_tenant.set_feature!("crm", false)

    assert_no_emails { CrmMessageDeliveryJob.perform_now(message.id) }
    assert message.reload.delivery_status_skipped?
    assert_equal "CRM is disabled for this tenant", message.delivery_last_error
  end
end
