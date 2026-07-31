require "test_helper"

class SavedViewsAndBulkActionsTest < ActionDispatch::IntegrationTest
  test "an agent saves, opens, and deletes a private case view" do
    sign_in_as users(:agent_a)

    assert_difference "SavedView.count", 1 do
      post saved_views_path, params: {
        resource_type: "cases", name: "High priority",
        filters: { priority: "high", unsafe: "discard me" }
      }
    end
    view = SavedView.order(:id).last
    assert_equal({ "priority" => "high" }, view.filters)
    assert_redirected_to cases_path(saved_view_id: view.id)

    follow_redirect!
    assert_response :success
    assert_select "select[name='saved_view_id'] option[selected]", text: "High priority"
    assert_select "select[name='priority'] option[selected][value='high']"
    assert_select "a", text: I18n.t("cases.index.my_tickets")

    assert_difference "SavedView.count", -1 do
      delete saved_view_path(view)
    end
    assert_redirected_to cases_path
  end

  test "one user cannot delete another user's saved view" do
    view = SavedView.create!(
      user: users(:admin), resource_type: "cases", name: "Admin only", filters: { status: "new" }
    )
    sign_in_as users(:agent_a)

    delete saved_view_path(view)

    assert_response :not_found
    assert SavedView.exists?(view.id)
  end

  test "case bulk priority is all-or-nothing across authorization" do
    allowed = cases(:pension_case)
    forbidden = cases(:assigned_case)
    original_allowed_priority = allowed.priority
    sign_in_as users(:agent_b)

    post bulk_update_cases_path, params: {
      case_ids: [ allowed.id, forbidden.id ], bulk_action: "priority", priority: "urgent"
    }

    assert_response :forbidden
    assert_equal original_allowed_priority, allowed.reload.priority
    assert_equal "high", forbidden.reload.priority
  end

  test "case bulk assignment updates selected cases" do
    sign_in_as users(:admin)
    selected = [ cases(:pension_case), cases(:waiting_case) ]

    post bulk_update_cases_path, params: {
      case_ids: selected.map(&:id), bulk_action: "assign", assignee_id: users(:agent_a).id
    }

    assert_redirected_to cases_path
    assert selected.all? { |kase| kase.reload.assignee == users(:agent_a) }
  end

  test "work views retain filters and bulk transition cannot cross projects" do
    project = projects(:pep)
    other_project = Project.create!(key: "OPS", name: "Operations", lead: users(:admin))
    other_item = other_project.work_items.create!(
      title: "Other workspace", workflow_state: other_project.workflow_states.first, reporter: users(:admin)
    )
    sign_in_as users(:admin)

    post saved_views_path, params: {
      resource_type: "work_items", context_id: project.id, name: "My open work",
      filters: { assignee_id: users(:agent_a).id, open: "1" }
    }
    view = SavedView.order(:id).last
    follow_redirect!
    assert_response :success
    assert_select "input[name='open'][checked]"
    assert_select "a", text: I18n.t("work_items.index.my_work")

    original_state = work_items(:pep_one).workflow_state
    post bulk_update_project_work_items_path(project), params: {
      work_item_ids: [ work_items(:pep_one).id, other_item.id ], bulk_action: "transition",
      workflow_state_id: workflow_states(:pep_done).id
    }

    assert_response :not_found
    assert_equal original_state, work_items(:pep_one).reload.workflow_state
    assert_equal other_project.workflow_states.first, other_item.reload.workflow_state
  end

  test "bulk endpoints reject more than one hundred records before mutation" do
    project = projects(:pep)
    state = workflow_states(:pep_backlog)
    items = 101.times.map do |i|
      project.work_items.create!(title: "Limit #{i}", workflow_state: state, reporter: users(:admin))
    end
    sign_in_as users(:admin)

    post bulk_update_project_work_items_path(project), params: {
      work_item_ids: items.map(&:id), bulk_action: "priority", priority: "urgent"
    }

    assert_response :bad_request
    assert items.none? { |item| item.reload.priority_urgent? }
  end
end
