require "test_helper"

# R3: BoardsController#show loaded EVERY work item in the project and grouped
# them in Ruby. Fine on a demo, a cliff on a real backlog — and the same shape
# as the deals pipeline. A kanban board is a working surface, not an archive.
class BoardScaleTest < ActionDispatch::IntegrationTest
  def project = projects(:pep)

  test "a column shows at most COLUMN_LIMIT cards however many exist" do
    state = workflow_states(:pep_backlog)
    (BoardsController::COLUMN_LIMIT + 15).times do |i|
      project.work_items.create!(title: "bulk #{i}", workflow_state: state, reporter: users(:admin))
    end

    sign_in_as users(:admin)
    get project_board_path(project)
    assert_response :success

    rendered = css_select("section[data-target-id='#{state.id}'] article.kanban-card").size
    assert_equal BoardsController::COLUMN_LIMIT, rendered,
                 "the board must not render an unbounded backlog"
  end

  test "the count shown is the TRUE total, not the number rendered" do
    state = workflow_states(:pep_backlog)
    total = BoardsController::COLUMN_LIMIT + 15
    (total - 1).times { |i| project.work_items.create!(title: "bulk #{i}", workflow_state: state, reporter: users(:admin)) }

    sign_in_as users(:admin)
    get project_board_path(project)

    # pep_one already sits in backlog, so the true total is `total`.
    assert_match(/#{total}/, response.body,
                 "a truncated column that reports its rendered count lies about the backlog")
    assert_match I18n.t("boards.show.see_all"), response.body,
                 "and it must offer the way to see the rest"
  end

  test "a small board is unchanged — no truncation notice, all cards shown" do
    sign_in_as users(:admin)
    get project_board_path(project)

    assert_response :success
    refute_match I18n.t("boards.show.see_all"), response.body
    assert_match work_items(:pep_one).reference, response.body
  end

  test "the board issues a bounded number of queries regardless of backlog size" do
    state = workflow_states(:pep_backlog)
    120.times { |i| project.work_items.create!(title: "bulk #{i}", workflow_state: state, reporter: users(:admin)) }
    sign_in_as users(:admin)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get project_board_path(project)
    end

    assert queries < 60, "board issued #{queries} queries — it should not scale with backlog size"
  end
end
