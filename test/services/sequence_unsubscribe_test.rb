require "test_helper"

class SequenceUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @sequence = Sequence.new(name: "Consent sequence")
    @sequence.sequence_steps.build(position: 0, delay_days: 0, subject: "Hello", body: "Welcome")
    @sequence.save!
    @lead = Lead.create!(name: "Opted in", email: "opted-in@example.test", email_consent: true)
    @enrollment = @sequence.enroll!(@lead)
    @token = SequenceUnsubscribe.token_for(@lead)
  end

  test "unsubscribe revokes consent, timestamps the target, and cancels active outreach" do
    result = SequenceUnsubscribe.call(@token)

    refute @lead.reload.email_consent?
    assert @lead.email_unsubscribed_at.present?
    assert @enrollment.reload.status_cancelled?
    assert_equal 1, result.cancelled_enrollments

    repeated = SequenceUnsubscribe.call(@token)
    assert_equal 0, repeated.cancelled_enrollments
  end

  test "a token cannot unsubscribe a replacement email or be tampered with" do
    @lead.update!(email: "replacement@example.test")
    assert_raises(SequenceUnsubscribe::InvalidToken) { SequenceUnsubscribe.call(@token) }
    assert_raises(SequenceUnsubscribe::InvalidToken) { SequenceUnsubscribe.call("#{@token}tampered") }
    assert @lead.reload.email_consent?
  end

  test "explicit re-opt-in clears the unsubscribe timestamp" do
    SequenceUnsubscribe.call(@token)
    @lead.update!(email_consent: true)

    assert @lead.email_consent?
    assert_nil @lead.email_unsubscribed_at
  end
end
