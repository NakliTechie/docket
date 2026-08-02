require "test_helper"

class KnowledgeCategoryTest < ActiveSupport::TestCase
  test "builds a display path and traverses descendants" do
    root = KnowledgeCategory.create!(name: "Benefits")
    child = KnowledgeCategory.create!(name: "Pensions", parent: root)
    leaf = KnowledgeCategory.create!(name: "Arrears", parent: child)

    assert_equal "Benefits / Pensions / Arrears", leaf.display_path
    assert_equal [ root, child, leaf ], root.self_and_descendants
  end

  test "rejects self and descendant parent loops" do
    root = KnowledgeCategory.create!(name: "Services")
    child = KnowledgeCategory.create!(name: "Applications", parent: root)

    root.parent = child
    assert_not root.valid?
    assert root.errors[:parent].any?

    child.parent = child
    assert_not child.valid?
    assert child.errors[:parent].any?
  end

  test "category names may repeat under different parents" do
    first = KnowledgeCategory.create!(name: "Department A")
    second = KnowledgeCategory.create!(name: "Department B")

    assert KnowledgeCategory.create(name: "Policies", parent: first).persisted?
    assert KnowledgeCategory.create(name: "Policies", parent: second).persisted?
  end
end
