require "test_helper"

class CaseCollaborationTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "case presence reports other viewers and can be released" do
    kase = cases(:pension_case)
    CasePresence.touch_for!(kase, users(:agent_a))

    post case_presence_path(kase), as: :json

    assert_response :success
    assert_equal [ users(:agent_a).name ], response.parsed_body["agents"]
    assert CasePresence.exists?(case: kase, user: users(:admin))

    delete case_presence_path(kase), as: :json
    assert_response :no_content
    refute CasePresence.exists?(case: kase, user: users(:admin))
  end

  test "merge redirects the old case identity to its canonical case" do
    target = cases(:pension_case)
    source = Case.create!(subject: "Duplicate", contact: target.contact, channel: :staff)

    post merge_case_path(target), params: { source_case_id: source.id }
    assert_redirected_to case_path(target)

    get case_path(source)
    assert_response :success
    assert_select "h1", text: target.subject
    assert_select "h1", text: source.subject, count: 0
  end

  test "split creates a case from selected messages" do
    source = cases(:pension_case)
    selected = source.messages.create!(body: "Separate me", kind: :internal_note,
                                       author: users(:admin))

    assert_difference "Case.count", 1 do
      post split_case_path(source), params: { subject: "New topic", message_ids: [ selected.id ] }
    end

    created = Case.order(:id).last
    assert_redirected_to case_path(created)
    assert_equal created, selected.reload.case
  end

  test "an author can edit and delete their own work comment" do
    comment = work_items(:pep_one).work_comments.create!(body: "Initial", author: users(:admin))

    patch work_comment_path(comment), params: { work_comment: { body: "Corrected" } }
    assert_redirected_to work_item_path(comment.work_item)
    assert_equal "Corrected", comment.reload.body

    delete work_comment_path(comment)
    assert_redirected_to work_item_path(comment.work_item)
    refute WorkComment.exists?(comment.id)
  end

  test "one user cannot rewrite another user's work comment" do
    comment = work_items(:pep_one).work_comments.create!(body: "Agent words", author: users(:agent_a))

    patch work_comment_path(comment), params: { work_comment: { body: "Admin rewrite" } }

    assert_response :forbidden
    assert_equal "Agent words", comment.reload.body
  end
end
