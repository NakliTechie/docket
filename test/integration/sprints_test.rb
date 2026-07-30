require "test_helper"

# WM3 — sprint planning and close-out, plus the reporting computed from them.
class SprintsTest < ActionDispatch::IntegrationTest
  def project = projects(:pep)

  test "a sprint is created, started, and scopes the board" do
    sign_in_as users(:admin)

    assert_difference "Sprint.count", 1 do
      post project_sprints_path(project), params: { sprint: { name: "Sprint 1", goal: "Ship the importer" } }
    end
    sprint = Sprint.order(:id).last
    assert sprint.status_planned?

    post start_project_sprint_path(project, sprint)
    assert sprint.reload.status_active?

    work_items(:pep_one).update!(sprint: sprint)
    get project_board_path(project)
    assert_response :success
    assert_match sprint.name, response.body, "the board says which sprint it is showing"
  end

  test "only one sprint can be active per project" do
    a = project.sprints.create!(name: "A", status: :active)
    b = project.sprints.new(name: "B", status: :active)

    refute b.valid?
    assert b.errors.of_kind?(:status, :another_sprint_active)
    assert a.reload.status_active?
  end

  test "closing sends unfinished work to the backlog by default and keeps finished work" do
    sprint = project.sprints.create!(name: "S1", status: :active)
    open_item = work_items(:pep_one)
    done_item = work_items(:pep_two)
    open_item.update!(sprint: sprint)
    done_item.update!(sprint: sprint)
    done_item.transition_to!(workflow_states(:pep_done))

    sign_in_as users(:admin)
    post close_project_sprint_path(project, sprint)

    assert sprint.reload.status_closed?
    assert_nil open_item.reload.sprint, "unfinished work returns to the backlog"
    assert_equal sprint, done_item.reload.sprint,
                 "finished work stays — the closed sprint is the record velocity is computed from"
  end

  test "unfinished work can roll forward into a named sprint instead" do
    current = project.sprints.create!(name: "S1", status: :active)
    nxt = project.sprints.create!(name: "S2")
    work_items(:pep_one).update!(sprint: current)

    sign_in_as users(:admin)
    post close_project_sprint_path(project, current), params: { roll_to: nxt.id }

    assert_equal nxt, work_items(:pep_one).reload.sprint
  end

  test "velocity counts completed estimate, not item count" do
    sprint = project.sprints.create!(name: "S1", status: :active)
    small = work_items(:pep_one)
    big = work_items(:pep_two)
    small.update!(sprint: sprint, estimate: 1)
    big.update!(sprint: sprint, estimate: 13)
    big.transition_to!(workflow_states(:pep_done))

    row = Sprints::Velocity.call(project: project)[:sprints].find { |r| r[:name] == "S1" }
    assert_equal 2, row[:committed]
    assert_equal 1, row[:completed]
    assert_equal 13.0, row[:completed_estimate], "one 13-point item is not one point"
    assert_equal 14.0, row[:committed_estimate]
  end

  test "cycle time is a median so one ancient item cannot distort it" do
    project.work_items.create!(title: "quick", reporter: users(:admin),
                               created_at: 2.days.ago, closed_at: 1.day.ago,
                               workflow_state: workflow_states(:pep_done))
    project.work_items.create!(title: "also quick", reporter: users(:admin),
                               created_at: 3.days.ago, closed_at: 2.days.ago,
                               workflow_state: workflow_states(:pep_done))
    project.work_items.create!(title: "ancient", reporter: users(:admin),
                               created_at: 400.days.ago, closed_at: Time.current,
                               workflow_state: workflow_states(:pep_done))

    days = Sprints::Velocity.call(project: project)[:cycle_time_days]
    assert days < 5, "median must not be dragged by the 400-day outlier (got #{days})"
  end

  test "the sprint page renders velocity and cycle-time reporting" do
    sprint = project.sprints.create!(name: "Measured sprint", status: :active)
    item = work_items(:pep_two)
    item.update!(sprint: sprint, estimate: 8)
    item.transition_to!(workflow_states(:pep_done))
    sign_in_as users(:admin)

    get project_sprints_path(project)

    assert_response :success
    assert_select "#sprint-report-title", text: I18n.t("sprints.index.report.title")
    assert_match "Measured sprint", response.body
    assert_match "8.0 / 8.0", response.body
  end

  test "sprints follow the work.sprints entitlement" do
    ActsAsTenant.current_tenant.set_feature!("work.sprints", false)
    sign_in_as users(:admin)

    get project_sprints_path(project)
    assert_response :not_found
  end

  test "running a sprint is work:write, not project:manage" do
    sprint = project.sprints.create!(name: "S1")
    sign_in_as users(:agent_a) # customer_service: work:read + work:write

    post start_project_sprint_path(project, sprint)
    assert sprint.reload.status_active?, "a team lead runs their own cadence"
  end

  # ── Regressions from the 2026-07-28 adversarial review ────────────────────
  test "a closed sprint still reports what it COMMITTED to, not just what survived" do
    sprint = project.sprints.create!(name: "S1", status: :active)
    done = work_items(:pep_two)
    unfinished = work_items(:pep_one)
    done.update!(sprint: sprint, estimate: 5)
    unfinished.update!(sprint: sprint, estimate: 8)
    done.transition_to!(workflow_states(:pep_done))

    Sprints::Closeout.call(sprint: sprint)

    row = Sprints::Velocity.call(project: project)[:sprints].find { |r| r[:name] == "S1" }
    assert_equal 2, row[:committed], "the rolled-out item is still part of the commitment"
    assert_equal 1, row[:completed]
    assert_equal 13.0, row[:committed_estimate]
    assert_equal 5.0, row[:completed_estimate]
    refute_equal row[:committed], row[:completed],
                 "counting only survivors made every closed sprint show 100% delivery"
  end

  test "close-out refuses the nonsense cases instead of silently lying" do
    sprint = project.sprints.create!(name: "S1", status: :active)
    other_project = Project.create!(key: "OTH", name: "Other")

    assert_raises(ArgumentError) { Sprints::Closeout.call(sprint: sprint, roll_to: sprint) }
    assert_raises(ArgumentError) do
      Sprints::Closeout.call(sprint: sprint, roll_to: other_project.sprints.create!(name: "X"))
    end
    closed = project.sprints.create!(name: "Old", status: :closed)
    assert_raises(ArgumentError) { Sprints::Closeout.call(sprint: sprint, roll_to: closed) }

    Sprints::Closeout.call(sprint: sprint)
    assert_raises(ArgumentError) { Sprints::Closeout.call(sprint: sprint) }
  end

  test "the console reports a refused close-out instead of raising" do
    sprint = project.sprints.create!(name: "S1", status: :active)
    sign_in_as users(:admin)

    post close_project_sprint_path(project, sprint), params: { roll_to: sprint.id }
    assert_redirected_to project_sprints_path(project)
    assert flash[:alert].present?
    assert sprint.reload.status_active?, "nothing was closed"
  end
end
