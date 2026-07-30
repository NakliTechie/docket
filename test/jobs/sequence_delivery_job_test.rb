require "test_helper"

class SequenceDeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  def pending_email_delivery
    sequence = Sequence.new(name: "Welcome")
    sequence.sequence_steps.build(position: 0, delay_days: 0, subject: "Hello", body: "Welcome")
    sequence.save!
    enrollment = sequence.enroll!(Lead.create!(name: "Asha", email: "asha.delivery@example.com"))
    enrollment.advance!
    clear_enqueued_jobs
    enrollment.sequence_deliveries.first
  end

  test "a receipt is claimed once and sends one email across repeated jobs" do
    delivery = pending_email_delivery

    assert_emails 1 do
      SequenceDeliveryJob.perform_now(delivery.id)
      SequenceDeliveryJob.perform_now(delivery.id)
    end

    assert delivery.reload.status_delivered?
    assert delivery.claimed_at.present?
    assert delivery.delivered_at.present?
  end

  test "an uncertain pre-claimed receipt is never replayed" do
    delivery = pending_email_delivery
    assert delivery.claim!

    assert_no_emails { SequenceDeliveryJob.perform_now(delivery.id) }
    assert delivery.reload.status_attempting?
  end

  test "the recovery sweep enqueues pending rows but not uncertain claims" do
    pending = pending_email_delivery
    uncertain = pending_email_delivery
    uncertain.claim!

    assert_enqueued_with(job: SequenceDeliveryJob, args: [ pending.id ]) do
      SequenceDeliverySweepJob.perform_now
    end
    assert_enqueued_jobs 1, only: SequenceDeliveryJob
  end

  test "pausing the SMS connector before dispatch records a skip" do
    connector = Connector.create!(name: "SMS", provider: "msg91", status: :active,
                                  config: { "template_id" => "T1" })
    connector.credentials_hash = { "authkey" => "k" }
    connector.save!
    sequence = Sequence.new(name: "SMS")
    sequence.sequence_steps.build(position: 0, delay_days: 0, channel: :sms, body: "Hello")
    sequence.save!
    enrollment = sequence.enroll!(
      Lead.create!(name: "Asha", phone: "+919900000001", sms_consent: true)
    )
    enrollment.advance!
    clear_enqueued_jobs
    delivery = enrollment.sequence_deliveries.first
    connector.update!(status: :paused)

    SequenceDeliveryJob.perform_now(delivery.id)

    assert delivery.reload.status_skipped?
    assert_includes delivery.last_error, "not active"
  end
end
