require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "renders the recipient locale and links to the inbox" do
    user = users(:agent_a)
    user.update_column(:locale, "hi")
    notification = Notifications::Publish.call(
      recipient: user, kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "hindi-mail", title: "Assigned", body: "Please review",
      metadata: { reference: "DKT-TEST-3456", subject: "Garbage not collected" }
    )

    mail = NotificationMailer.alert(notification)
    assert_equal I18n.t("notifications.events.assignment.title", locale: :hi), mail.subject
    assert_match I18n.t("notification_mailer.open_inbox", locale: :hi), mail.html_part.body.to_s
    assert_match "http://example.com/notifications", mail.html_part.body.to_s
  end
end
