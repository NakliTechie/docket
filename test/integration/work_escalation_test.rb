require "test_helper"

# WM4 — the seam that makes three modules one product. A support case hands work
# to engineering, and the desk keeps the customer conversation.
class WorkEscalationTest < ActionDispatch::IntegrationTest
  def kase = cases(:pension_case)

  test "escalating opens a linked work item and notes it on the case" do
    sign_in_as users(:admin)

    assert_difference [ "WorkItem.count", "WorkLink.count" ], 1 do
      post escalate_case_path(kase), params: { project_id: projects(:pep).id }
    end

    item = WorkItem.order(:id).last
    assert_equal kase.subject, item.title
    assert_equal kase.priority, item.priority, "urgency survives the hand-off"
    assert_equal users(:admin), item.reporter
    assert_equal "escalated_from", item.work_links.first.relation
    assert_includes kase.reload.work_items, item
  end

  test "the case is noted internally, never told to the customer" do
    sign_in_as users(:admin)
    post escalate_case_path(kase), params: { project_id: projects(:pep).id }

    note = kase.messages.order(:id).last
    assert note.kind_internal_note?, "the customer did not ask for a work item"
    assert_match WorkItem.order(:id).last.reference, note.body
  end

  test "escalating does not change the case status" do
    sign_in_as users(:admin)
    before = kase.status

    post escalate_case_path(kase), params: { project_id: projects(:pep).id }
    assert_equal before, kase.reload.status, "escalating is not a status change"
  end

  test "a work item's move echoes onto its linked case as an internal note" do
    item = work_items(:pep_one)
    WorkLink.create!(work_item: item, linkable: kase, relation: :escalated_from)

    assert_difference "kase.messages.count", 1 do
      item.transition_to!(workflow_states(:pep_done))
    end

    note = kase.messages.order(:id).last
    assert note.kind_internal_note?
    assert_match "Done", note.body
    assert_match item.reference, note.body
  end

  test "an unlinked item's move touches no case" do
    assert_no_difference "Message.count" do
      work_items(:pep_two).transition_to!(workflow_states(:pep_done))
    end
  end

  test "escalation needs the work module, not just the desk" do
    ActsAsTenant.current_tenant.set_feature!("work", false)
    sign_in_as users(:admin)

    assert_no_difference "WorkItem.count" do
      post escalate_case_path(kase), params: { project_id: projects(:pep).id }
    end
    assert_response :not_found
  end

  test "escalation needs work:write, not merely case access" do
    sign_in_as users(:readonly)

    assert_no_difference "WorkItem.count" do
      post escalate_case_path(kase), params: { project_id: projects(:pep).id }
    end
    assert_response :forbidden
  end

  test "the case workspace shows linked work and an escalate control" do
    sign_in_as users(:admin)
    WorkLink.create!(work_item: work_items(:pep_one), linkable: kase, relation: :escalated_from)

    get case_path(kase)
    assert_response :success
    assert_match work_items(:pep_one).reference, response.body
    assert_match I18n.t("work.escalation.escalate"), response.body
  end

  test "the panel disappears with the work module" do
    ActsAsTenant.current_tenant.set_feature!("work", false)
    sign_in_as users(:admin)

    get case_path(kase)
    assert_response :success
    refute_match I18n.t("work.escalation.panel_title"), response.body
  end

  test "a link is unique per item and record" do
    WorkLink.create!(work_item: work_items(:pep_one), linkable: kase)
    dup = WorkLink.new(work_item: work_items(:pep_one), linkable: kase)
    refute dup.valid?
  end
end
