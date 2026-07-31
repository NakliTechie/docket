require "test_helper"

class WorkRelationsAndAssignmentTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "a manager configures defaults and the work form accepts parent and sprint" do
    project = projects(:pep)
    patch project_path(project), params: { project: {
      name: project.name, key: project.key,
      work_assignment_rules_attributes: {
        "0" => { work_kind: "story", assignee_id: users(:technical).id }
      }
    } }
    assert_redirected_to projects_path

    sprint = project.sprints.create!(name: "Next", starts_on: Date.current,
                                     ends_on: 7.days.from_now.to_date)
    parent = work_items(:pep_one)
    post project_work_items_path(project), params: { work_item: {
      title: "Child story", kind: "story", parent_id: parent.id, sprint_id: sprint.id
    } }
    item = WorkItem.find_by!(title: "Child story")
    assert_equal parent, item.parent
    assert_equal sprint, item.sprint
    assert_equal users(:technical), item.assignee
  end

  test "staff add and remove a visible work relation" do
    source, target = work_items(:pep_one), work_items(:pep_two)
    post work_item_relations_path(source), params: { work_item_relation: {
      relation_type: "blocks", target_id: target.id
    } }
    assert_redirected_to work_item_path(source)
    relation = WorkItemRelation.find_by!(source: source, target: target)

    delete work_item_relation_path(relation)
    assert_redirected_to work_item_path(source)
    refute WorkItemRelation.exists?(relation.id)
  end
end
