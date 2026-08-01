require "test_helper"

class ProjectLifecycleTest < ActiveSupport::TestCase
  test "delete and restore atomically carry live children and preserve memberships" do
    project = Project.create!(key: "LIFE", name: "Lifecycle", visibility: :restricted,
                              member_ids: [ users(:agent_a).id ])
    item = project.work_items.create!(title: "Live item", reporter: users(:admin))
    live_sprint = project.sprints.create!(name: "Live sprint")
    independently_deleted = project.sprints.create!(name: "Old sprint")
    independently_deleted.destroy
    original_child_stamp = independently_deleted.deleted_at
    state_ids = project.workflow_states.ids
    membership_id = project.project_memberships.pick(:id)

    project.destroy!
    stamp = project.deleted_at

    refute Project.exists?(project.id)
    assert_equal [ stamp ], WorkflowState.with_deleted.where(id: state_ids).distinct.pluck(:deleted_at)
    assert_equal stamp, WorkItem.with_deleted.find(item.id).deleted_at
    assert_equal stamp, Sprint.with_deleted.find(live_sprint.id).deleted_at
    assert_equal original_child_stamp, Sprint.with_deleted.find(independently_deleted.id).deleted_at
    assert ProjectMembership.exists?(membership_id), "soft delete retains the restricted audience"

    project.restore!

    assert Project.exists?(project.id)
    assert_equal state_ids.sort, project.workflow_states.ids.sort
    assert WorkItem.exists?(item.id)
    assert Sprint.exists?(live_sprint.id)
    refute Sprint.exists?(independently_deleted.id), "a child deleted earlier stays deleted"
    assert_equal [ users(:agent_a).id ], project.member_ids
  end

  test "a failed project restore rolls child visibility back too" do
    project = Project.create!(key: "ROLL", name: "Original")
    item = project.work_items.create!(title: "Child", reporter: users(:admin))
    project.destroy!
    Project.create!(key: "ROLL", name: "Replacement")

    assert_raises(ActiveRecord::RecordInvalid) { project.restore! }
    assert WorkItem.with_deleted.find(item.id).deleted?,
           "children must not leak back when the parent restore cannot commit"
  end
end
