require "test_helper"

class RecordVisibilityTest < ActiveSupport::TestCase
  setup do
    @viewer = users(:client_admin)
    @peer = users(:agent_a)
    @outsider = users(:agent_b)
    @viewer.update!(record_read_scope: :global, record_write_scope: :global)

    cases(:pension_case).update_columns(owner_id: @viewer.id, assignee_id: @outsider.id)
    cases(:assigned_case).update_columns(owner_id: @outsider.id, assignee_id: @viewer.id)
    cases(:waiting_case).update_columns(owner_id: @outsider.id, assignee_id: @outsider.id)
    contacts(:asha).update_column(:owner_id, @peer.id)
    contacts(:ravi).update_column(:owner_id, @outsider.id)
    organisations(:dpg).update_column(:owner_id, @peer.id)
    organisations(:branch).update_column(:owner_id, @outsider.id)
    work_items(:pep_one).update_columns(reporter_id: @peer.id, assignee_id: @peer.id)
    work_items(:pep_two).update_columns(reporter_id: @outsider.id, assignee_id: @outsider.id)
  end

  test "global scope preserves tenant-wide visibility" do
    assert_equal Case.count, visible(Case).count
    assert_equal Contact.count, visible(Contact).count
    assert_equal WorkItem.count, visible(WorkItem).count
  end

  test "owned and assigned are distinct lenses" do
    @viewer.update!(record_read_scope: :owned)
    assert_includes visible(Case), cases(:pension_case)
    refute_includes visible(Case), cases(:assigned_case)

    @viewer.update!(record_read_scope: :assigned, record_write_scope: :assigned)
    assert_includes visible(Case), cases(:pension_case)
    assert_includes visible(Case), cases(:assigned_case)
    refute_includes visible(Case), cases(:waiting_case)
  end

  test "queue scope includes queue cases and their customer records" do
    @viewer.queue_memberships.create!(queue: queues(:pensions))
    @viewer.update!(record_read_scope: :queue)

    assert_includes visible(Case), cases(:pension_case)
    refute_includes visible(Case), cases(:waiting_case)
    assert_includes visible(Contact), contacts(:asha)
    assert_includes visible(Organisation), organisations(:dpg)
    refute_includes visible(Contact), contacts(:ravi)
  end

  test "team scope includes records owned or assigned across explicit teams" do
    team = Team.create!(name: "North desk")
    team.team_memberships.create!(user: @viewer)
    team.team_memberships.create!(user: @peer)
    cases(:assigned_case).update_column(:assignee_id, @peer.id)
    @viewer.update!(record_read_scope: :team)

    assert_includes visible(Case), cases(:assigned_case)
    assert_includes visible(Contact), contacts(:asha)
    assert_includes visible(WorkItem), work_items(:pep_one)
    refute_includes visible(WorkItem), work_items(:pep_two)
  end

  test "account scope includes assigned account descendants and linked work" do
    organisations(:branch).update!(parent: organisations(:dpg))
    @viewer.account_memberships.create!(organisation: organisations(:dpg))
    @viewer.update!(record_read_scope: :account)

    assert_includes visible(Organisation), organisations(:dpg)
    assert_includes visible(Organisation), organisations(:branch)
    assert_includes visible(Contact), contacts(:ravi)
    assert_includes visible(Case), cases(:assigned_case)

    link = WorkLink.create!(work_item: work_items(:pep_two), linkable: cases(:assigned_case))
    assert_includes visible(WorkItem), link.work_item
  end

  test "read and write scopes intersect policy permissions independently" do
    @viewer.update!(record_read_scope: :global, record_write_scope: :owned)
    owned = cases(:pension_case)
    assigned = cases(:assigned_case)

    assert_includes CasePolicy::Scope.new(@viewer, Case).resolve, assigned
    assert CasePolicy.new(@viewer, owned).update?
    refute CasePolicy.new(@viewer, assigned).update?
    assert CasePolicy.new(@viewer, assigned).show?
  end

  test "a visible work item makes its project container visible" do
    work_items(:pep_one).update_columns(reporter_id: @viewer.id, assignee_id: @viewer.id)
    projects(:pep).update_column(:lead_id, @outsider.id)
    @viewer.update!(record_read_scope: :assigned, record_write_scope: :assigned)

    assert_includes visible(WorkItem), work_items(:pep_one)
    assert_includes visible(Project), projects(:pep)
    assert_includes ProjectPolicy::Scope.new(@viewer, Project).resolve, projects(:pep)
    refute_includes visible(Project, access: :write), projects(:pep)
  end

  test "account and team memberships reject cross-tenant targets" do
    other_user, other_account = ActsAsTenant.with_tenant(tenants(:acme)) do
      [
        User.create!(name: "Other user", email_address: "other-scope@example.com",
                     password: "password1234", role: :customer_service),
        Organisation.create!(name: "Other account", kind: :company)
      ]
    end
    team = Team.create!(name: "Primary")

    refute team.team_memberships.new(user: other_user).valid?
    refute @viewer.account_memberships.new(organisation: other_account).valid?
  end

  private

  def visible(model, access: :read)
    RecordVisibility.resolve(@viewer, model.all, access: access)
  end
end
