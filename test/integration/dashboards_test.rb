require "test_helper"

# The operator dashboard composes the case-desk, sales, connector-ingestion and
# effector-accountability planes. Unlike the all-staff sales report, it is gated
# to admin + supervisor (the effector-governance plane is sensitive).
class DashboardsTest < ActionDispatch::IntegrationTest
  test "an admin sees the dashboard with every plane" do
    sign_in_as users(:admin)
    get dashboard_path
    assert_response :success
    assert_match "Dashboard", response.body
    assert_match "Case desk", response.body
    assert_match "Connectors &amp; ingestion", response.body
    assert_match "Agent accountability", response.body
    assert_match "Autonomy rate", response.body
  end

  test "a supervisor may see the dashboard" do
    sign_in_as users(:supervisor)
    get dashboard_path
    assert_response :success
  end

  test "a role without report:operational is forbidden" do
    sign_in_as users(:sales)
    get dashboard_path
    assert_response :forbidden
  end

  test "the dashboard exports a combined KPI CSV" do
    sign_in_as users(:admin)
    get dashboard_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", @response.media_type
    assert_match "section,metric,value,from,to", response.body
    assert_match "effector,autonomy_rate_pct", response.body
  end

  test "the nav links admin/supervisor to the dashboard but not an agent" do
    sign_in_as users(:admin)
    get cases_path
    assert_match(%r{href="/dashboard"}, response.body)

    sign_in_as users(:sales)
    get cases_path
    assert_no_match(%r{href="/dashboard"}, response.body)
  end

  test "an anonymous visitor is bounced to sign in" do
    get dashboard_path
    assert_redirected_to new_session_path
  end
end
