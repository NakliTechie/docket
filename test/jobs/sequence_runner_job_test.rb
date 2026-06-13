require "test_helper"

class SequenceRunnerJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  def two_step_sequence
    seq = Sequence.new(name: "Welcome")
    seq.sequence_steps.build(position: 0, delay_days: 0, subject: "Hi {{contact_name}}", body: "Welcome!")
    seq.sequence_steps.build(position: 1, delay_days: 5, subject: "Day 5", body: "Still here?")
    seq.save!
    seq
  end

  test "advances a due enrollment, sends the step, and schedules the next" do
    seq = two_step_sequence
    lead = Lead.create!(name: "Asha", email: "asha.seq@example.com")
    enr = seq.enroll!(lead)

    assert_enqueued_email_with CrmMailer, :sequence_step, args: [ enr, seq.ordered_steps.first ] do
      SequenceRunnerJob.perform_now
    end

    enr.reload
    assert_equal 1, enr.current_step_position
    assert enr.status_active?
    assert enr.next_run_at > Time.current # waiting for the 5-day step
  end

  test "completes the enrollment after the last step" do
    seq = two_step_sequence
    lead = Lead.create!(name: "Bee", email: "bee.seq@example.com")
    enr = seq.enroll!(lead)

    SequenceRunnerJob.perform_now            # step 0 sent, advance to 1
    enr.update_columns(next_run_at: 1.minute.ago) # make the 2nd step due now
    SequenceRunnerJob.perform_now            # step 1 sent, no next -> completed

    assert enr.reload.status_completed?
    assert_nil enr.next_run_at
  end

  test "does not advance an enrollment that is not yet due" do
    seq = two_step_sequence
    lead = Lead.create!(name: "Future", email: "future.seq@example.com")
    enr = seq.enroll!(lead)
    enr.update_columns(next_run_at: 2.days.from_now)

    assert_no_enqueued_emails do
      SequenceRunnerJob.perform_now
    end
    assert_equal 0, enr.reload.current_step_position
  end

  test "skips delivery when the target has no email but still advances" do
    seq = two_step_sequence
    lead = Lead.create!(name: "Phone Only", phone: "+919999999999")
    enr = seq.enroll!(lead)
    assert_no_enqueued_emails { SequenceRunnerJob.perform_now }
    assert_equal 1, enr.reload.current_step_position
  end

  def sms_sequence
    seq = Sequence.new(name: "SMS welcome")
    seq.sequence_steps.build(position: 0, delay_days: 0, channel: :sms, body: "SMS step")
    seq.save!
    seq
  end

  def active_sms_connector
    c = Connector.create!(name: "SMS", provider: "msg91", status: :active, config: { "template_id" => "T1" })
    c.credentials_hash = { "authkey" => "k" }
    c.save!
    c
  end

  test "an SMS step enqueues delivery for a consenting recipient when a connector is wired" do
    active_sms_connector
    seq = sms_sequence
    lead = Lead.create!(name: "Opted In", phone: "+919900000001", sms_consent: true)
    seq.enroll!(lead)
    assert_enqueued_with(job: SmsDeliveryJob) { SequenceRunnerJob.perform_now }
  end

  test "an SMS step is skipped without consent, but the enrollment still advances" do
    active_sms_connector
    seq = sms_sequence
    lead = Lead.create!(name: "No Consent", phone: "+919900000002", sms_consent: false)
    enr = seq.enroll!(lead)
    assert_no_enqueued_jobs(only: SmsDeliveryJob) { SequenceRunnerJob.perform_now }
    assert_equal 1, enr.reload.current_step_position
  end
end
