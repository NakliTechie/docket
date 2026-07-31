require "test_helper"

class NotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @notification = Notifications::Publish.call(
      recipient: users(:agent_a), kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "inbox", title: "Assigned", body: "Please review",
      metadata: { reference: "DKT-TEST-3456", subject: "Garbage not collected" }
    )
  end

  test "recipient can list, filter, read, and mark all notifications" do
    sign_in_as users(:agent_a)

    get notifications_path(status: "unread")
    assert_response :success
    assert_match I18n.t("notifications.events.assignment.title"), response.body

    patch read_notification_path(@notification)
    assert_redirected_to case_path(cases(:assigned_case))
    assert_not @notification.reload.unread?

    another = Notifications::Publish.call(
      recipient: users(:agent_a), kind: :mention, notifiable: cases(:pension_case),
      dedupe_key: "another", title: "Mention", body: "Mentioned",
      metadata: { actor: "Anita", reference: "DKT-TEST-2345" }, actor: nil
    )
    patch read_all_notifications_path
    assert_redirected_to notifications_path
    assert_not another.reload.unread?
  end

  test "another user cannot see or mutate a recipient's notification" do
    sign_in_as users(:agent_b)

    get notifications_path
    assert_response :success
    refute_match "DKT-TEST-3456", response.body
    patch read_notification_path(@notification)
    assert_response :not_found
    assert @notification.reload.unread?
  end
end
