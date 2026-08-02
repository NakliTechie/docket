require "test_helper"

class CrmMailerTest < ActionMailer::TestCase
  test "sequence mail carries one-click unsubscribe headers and links" do
    sequence = Sequence.new(name: "Mail consent")
    sequence.sequence_steps.build(position: 0, delay_days: 0, subject: "Hello",
                                  body: "Welcome: https://example.test/offer")
    sequence.save!
    lead = Lead.create!(name: "Recipient", email: "recipient@example.test", email_consent: true)
    enrollment = sequence.enroll!(lead)
    enrollment.advance!
    delivery = enrollment.sequence_deliveries.first

    mail = CrmMailer.sequence_delivery(delivery)
    unsubscribe_url = SequenceUnsubscribe.url_for(lead)

    assert_equal "<#{unsubscribe_url}>", mail["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].value
    assert_includes mail.html_part.body.decoded, unsubscribe_url
    assert_includes mail.text_part.body.decoded, unsubscribe_url
    assert_includes mail.html_part.body.decoded, "/sequence_tracking/"
    assert_includes mail.html_part.body.decoded, "open.gif"
    assert_equal SequenceTracking.reply_address(delivery), mail.reply_to.first
  end
end
