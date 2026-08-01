require "test_helper"

class WorkItemRelationTest < ActiveSupport::TestCase
  test "blocks are directional and expose only open blockers" do
    source = work_items(:pep_one)
    target = work_items(:pep_two)
    WorkItemRelation.create!(source: source, target: target, relation_type: "blocks",
                             created_by: users(:admin))

    assert_equal [ source ], target.open_blockers
    source.transition_to!(source.project.workflow_states.find_by!(category: :done))
    assert_empty target.open_blockers
  end

  test "duplicate pairs canonicalize so reverse duplicates cannot be inserted" do
    first, second = work_items(:pep_one), work_items(:pep_two)
    relation = WorkItemRelation.create!(source: second, target: first,
                                        relation_type: "duplicates")
    assert_operator relation.source_id, :<, relation.target_id

    reverse = WorkItemRelation.new(source: first, target: second, relation_type: "duplicates")
    refute reverse.valid?
  end

  test "self relationships are rejected" do
    item = work_items(:pep_one)
    relation = WorkItemRelation.new(source: item, target: item, relation_type: "blocks")
    refute relation.valid?
  end
end
