require "application_system_test_case"

class NotificationBadgeTest < ApplicationSystemTestCase
  test "unread badge updates live without refreshing a list" do
    user = users(:agent_a)
    sign_in_with_form(user)
    assert_no_selector ".badge-notification"
    assert_selector "turbo-cable-stream-source[connected]", visible: :all

    notification = Notifications::Publish.call(
      recipient: user, kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "live-badge", title: "Assigned", body: "Please review",
      metadata: { reference: "DKT-TEST-3456", subject: "Garbage not collected" }
    )
    # Transactional system tests hold after_commit until teardown. Broadcast the
    # already-renderable state explicitly; production uses Notification's
    # after_commit callback for this exact operation.
    notification.send(:broadcast_badge)

    assert_selector ".badge-notification", text: "1"
  end
end
