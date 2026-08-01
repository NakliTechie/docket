require "test_helper"

class ActivitiesTest < ActionDispatch::IntegrationTest
  test "a rep logs an activity on a contact, sees it in the queue, completes and deletes it" do
    sign_in_as users(:sales)
    contact = contacts(:asha)

    get new_activity_path(subject_type: "Contact", subject_id: contact.id)
    assert_response :success

    assert_difference "Activity.count", 1 do
      post activities_path, params: { activity: {
        subject_type: "Contact", subject_id: contact.id, kind: "call",
        title: "Follow up on quote", owner_id: users(:sales).id, due_at: 1.day.from_now
      } }
    end
    activity = Activity.order(:id).last
    assert_equal contact, activity.subject
    assert_equal users(:sales), activity.owner

    get activities_path
    assert_response :success
    assert_includes response.body, "Follow up on quote"

    patch complete_activity_path(activity)
    assert activity.reload.status_done?

    delete activity_path(activity)
    assert_not Activity.exists?(activity.id)
  end

  test "the queue shows the current user's open activities and hides others'" do
    sign_in_as users(:sales)
    Activity.create!(title: "mine open", subject: contacts(:asha), owner: users(:sales))
    Activity.create!(title: "someone else", subject: contacts(:asha), owner: users(:agent_a))

    get activities_path
    assert_includes response.body, "mine open"
    assert_not_includes response.body, "someone else"
  end

  test "a read-only user cannot create an activity" do
    sign_in_as users(:readonly)
    assert_no_difference "Activity.count" do
      post activities_path, params: { activity: { subject_type: "Contact", subject_id: contacts(:asha).id, title: "x" } }
    end
    assert_response :forbidden
  end
end
