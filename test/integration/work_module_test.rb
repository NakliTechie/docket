require "test_helper"

# The Work module end to end through the console: create a project, work an item
# across the board, comment on it. Also pins the two seams that make it part of
# ONE product rather than a bolted-on tracker: the `work` entitlement and the
# work:write / project:manage authority split.
class WorkModuleTest < ActionDispatch::IntegrationTest
  test "a project can be created, worked and archived" do
    sign_in_as users(:admin)

    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { key: "ops", name: "Operations" } }
    end
    project = Project.order(:id).last
    assert_equal "OPS", project.key, "keys normalize on the way in"
    assert_redirected_to project_board_path(project)
    assert_equal Project::DEFAULT_STATES.size, project.workflow_states.count

    get project_board_path(project)
    assert_response :success

    post archive_project_path(project)
    assert project.reload.archived?
  end

  test "an item moves across the board and the move is audited" do
    sign_in_as users(:admin)
    item = work_items(:pep_one)

    assert_difference "AuditEntry.count", 1 do
      post transition_work_item_path(item, workflow_state_id: workflow_states(:pep_done).id)
    end

    assert_equal workflow_states(:pep_done), item.reload.workflow_state
    assert item.done?
  end

  test "the workspace shows an item and takes a comment" do
    sign_in_as users(:agent_a)
    item = work_items(:pep_two)

    get work_item_path(item)
    assert_response :success
    assert_match item.reference, response.body

    assert_difference "WorkComment.count", 1 do
      post work_item_work_comments_path(item), params: { work_comment: { body: "Picked this up." } }
    end
    assert_equal users(:agent_a), WorkComment.order(:id).last.author
  end

  test "creating an item stamps the reporter and mints the next reference" do
    sign_in_as users(:agent_a)

    post project_work_items_path(projects(:pep)),
         params: { work_item: { title: "Backfill imports", kind: "bug", priority: "high" } }

    item = WorkItem.order(:id).last
    assert_equal users(:agent_a), item.reporter
    assert_equal "PEP-3", item.reference
    assert_redirected_to work_item_path(item)
  end

  test "watching is a toggle" do
    sign_in_as users(:agent_a)
    item = work_items(:pep_one)

    post watch_work_item_path(item)
    assert_includes item.reload.watchers, users(:agent_a)

    post watch_work_item_path(item)
    refute_includes item.reload.watchers, users(:agent_a)
  end

  # ── Authority ─────────────────────────────────────────────────────────────
  test "work:write can move items but cannot create projects" do
    sign_in_as users(:agent_a) # customer_service: work:read + work:write, no project:manage

    post transition_work_item_path(work_items(:pep_one), workflow_state_id: workflow_states(:pep_done).id)
    assert_response :redirect, "moving work is work:write"

    post projects_path, params: { project: { key: "NOPE", name: "Not allowed" } }
    assert_response :forbidden, "creating a workspace is project:manage"
  end

  test "a read-only role can look but not touch" do
    sign_in_as users(:readonly)

    get projects_path
    assert_response :success

    post transition_work_item_path(work_items(:pep_one), workflow_state_id: workflow_states(:pep_done).id)
    assert_response :forbidden
  end

  test "only the author may edit their own comment" do
    comment = work_items(:pep_one).work_comments.create!(body: "mine", author: users(:agent_a))

    assert WorkCommentPolicy.new(users(:agent_a), comment).update?
    refute WorkCommentPolicy.new(users(:admin), comment).update?,
           "even a super_admin does not rewrite someone else's words"
  end

  # ── Entitlement ───────────────────────────────────────────────────────────
  test "with the work module off, the whole surface is gone" do
    ActsAsTenant.current_tenant.set_feature!("work", false)
    sign_in_as users(:admin)

    get projects_path
    assert_response :not_found

    get work_item_path(work_items(:pep_one))
    assert_response :not_found

    post transition_work_item_path(work_items(:pep_one), workflow_state_id: workflow_states(:pep_done).id)
    assert_response :not_found
    assert_equal workflow_states(:pep_backlog), work_items(:pep_one).reload.workflow_state,
                 "a gated request must not have side effects"
  end

  test "with the work module off, no role holds its permissions" do
    ActsAsTenant.current_tenant.set_feature!("work", false)
    refute users(:admin).can?("work:read")
    refute users(:admin).can?("project:manage")
  end
end
