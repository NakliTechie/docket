require "test_helper"

class WorkAssignmentRuleTest < ActiveSupport::TestCase
  test "a project-kind rule assigns new work but never overwrites an explicit assignee" do
    project = projects(:pep)
    WorkAssignmentRule.create!(project: project, work_kind: "bug", assignee: users(:technical))

    automatic = project.work_items.create!(title: "Production bug", kind: :bug,
                                           reporter: users(:admin))
    assert_equal users(:technical), automatic.assignee

    explicit = project.work_items.create!(title: "Owned bug", kind: :bug,
                                          assignee: users(:agent_a), reporter: users(:admin))
    assert_equal users(:agent_a), explicit.assignee
  end

  test "inactive assignees cannot be configured" do
    rule = WorkAssignmentRule.new(project: projects(:pep), work_kind: "task",
                                  assignee: users(:inactive))
    refute rule.valid?
  end
end
