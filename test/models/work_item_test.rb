require "test_helper"

class WorkItemTest < ActiveSupport::TestCase
  def project = projects(:pep)

  test "a new project seeds its default board columns" do
    fresh = Project.create!(key: "new", name: "Fresh")
    assert_equal Project::DEFAULT_STATES.map { _1[:name] }, fresh.workflow_states.ordered.map(&:name)
    assert_equal "NEW", fresh.key, "keys normalize to uppercase"
  end

  test "keys are validated and unique per tenant" do
    refute Project.new(key: "lower case", name: "x").valid?
    refute Project.new(key: "PEP", name: "dup").valid?, "PEP already exists in this tenant"

    ActsAsTenant.with_tenant(tenants(:acme)) do
      assert Project.new(key: "PEP", name: "same key, other tenant").valid?
    end
  end

  test "an item gets KEY-n identity from its project" do
    item = project.work_items.create!(title: "Ship it", reporter: users(:admin))
    assert_equal "PEP-3", item.reference, "fixtures already hold 1 and 2"
    assert_equal project.default_state, item.workflow_state, "lands in the first column"
  end

  test "numbers do not collide under concurrent creation" do
    numbers = 4.times.map { project.work_items.create!(title: "n", reporter: users(:admin)).number }
    assert_equal numbers.uniq, numbers
    assert_equal numbers.sort, numbers.uniq.sort
  end

  test "the allocator heals a counter left behind by a bulk import" do
    # What an importer does: writes numbers straight through, counter untouched.
    project.work_items.create!(title: "imported", number: 900, reporter: users(:admin))
    project.update_column(:last_item_number, 2)

    item = project.work_items.create!(title: "after import", reporter: users(:admin))
    assert_equal 901, item.number, "must clear the highest existing number, not reissue 3"
  end

  test "a deleted item's number is never reissued" do
    project.work_items.create!(title: "gone", number: 500, reporter: users(:admin)).destroy
    item = project.work_items.create!(title: "next", reporter: users(:admin))
    assert_equal 501, item.number
  end

  test "closed_at is stamped on entering a done column and cleared on leaving" do
    item = work_items(:pep_one)
    assert_nil item.closed_at

    item.transition_to!(workflow_states(:pep_done))
    assert item.done?
    assert_not_nil item.closed_at

    item.transition_to!(workflow_states(:pep_in_progress))
    assert_nil item.closed_at, "reopening must not leave a stale completion time"
  end

  test "a state from another project is rejected" do
    item = work_items(:pep_one)
    item.workflow_state = workflow_states(:acme_backlog)
    refute item.valid?
    assert item.errors.of_kind?(:workflow_state, :not_in_project)
  end

  test "an item cannot be its own parent, nor form a cycle" do
    a = work_items(:pep_one)
    b = work_items(:pep_two)

    a.parent = a
    refute a.valid?
    a.reload

    b.update!(parent: a)
    a.parent = b
    refute a.valid?, "A -> B -> A is a cycle"
    assert a.errors.of_kind?(:parent, :cycle)
  end

  test "open and closed scopes read the column category, not its name" do
    assert_includes WorkItem.open, work_items(:pep_one)
    work_items(:pep_one).transition_to!(workflow_states(:pep_done))
    assert_includes WorkItem.closed, work_items(:pep_one)
    refute_includes WorkItem.open, work_items(:pep_one)
  end

  test "soft delete hides an item but keeps it reachable for audit" do
    item = work_items(:pep_one)
    item.destroy
    assert_empty WorkItem.where(id: item.id)
    assert_equal 1, WorkItem.with_deleted.where(id: item.id).count
  end

  test "items are tenant-scoped" do
    ActsAsTenant.with_tenant(tenants(:acme)) do
      assert_empty WorkItem.where(id: work_items(:pep_one).id)
    end
  end

  test "estimate must not be negative" do
    item = work_items(:pep_one)
    item.estimate = -1
    refute item.valid?
  end

  # ── Regressions from the 2026-07-28 adversarial review ────────────────────
  test "deleting a project that holds work items does not raise" do
    assert_nothing_raised { project.destroy }
    assert project.reload.deleted?, "soft-deleted, not blocked"
    assert_equal 2, WorkItem.with_deleted.where(project: project).count,
                  "the items stay intact behind the hidden project"
  end

  test "soft-deleting a sprint does not strip its items' sprint_id" do
    sprint = project.sprints.create!(name: "S1")
    item = work_items(:pep_one)
    item.update!(sprint: sprint)

    sprint.destroy
    assert_equal sprint.id, item.reload.sprint_id,
                 "a restore must be able to recover the sprint's history"

    sprint.restore!
    assert_equal sprint, item.reload.sprint
  end

  test "soft-deleting a parent does not permanently flatten the hierarchy" do
    parent = work_items(:pep_one)
    child = work_items(:pep_two)
    child.update!(parent: parent)

    parent.destroy
    assert_equal parent.id, child.reload.parent_id
    parent.restore!
    assert_includes parent.reload.children, child
  end

  test "an item cannot be its own parent on CREATE either" do
    item = project.work_items.new(title: "self", reporter: users(:admin))
    item.parent = item
    refute item.valid?, "parent_id is blank on an unsaved record — the object must be checked too"
    assert item.errors.of_kind?(:parent, :cannot_be_self)
  end

  test "a parent from another project is rejected" do
    other = Project.create!(key: "OTH", name: "Other")
    foreign = other.work_items.create!(title: "elsewhere", reporter: users(:admin))

    item = work_items(:pep_one)
    item.parent = foreign
    refute item.valid?, "a work item tree must not span projects"
    assert item.errors.of_kind?(:parent, :not_in_project)
  end
end
