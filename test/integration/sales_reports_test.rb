require "test_helper"

# The sales/pipeline dashboard — value by stage, win/loss, lead conversion —
# is visible to all staff (like the deals + pipelines lists it summarizes),
# with a CSV export, mirroring the Activity report.
class SalesReportsTest < ActionDispatch::IntegrationTest
  test "a staff member sees the sales dashboard with its key figures" do
    sign_in_as users(:agent_a)
    get sales_report_path
    assert_response :success
    assert_match "Sales report", response.body
    assert_match "Open pipeline (now)", response.body
    assert_match "Win rate", response.body
  end

  test "the dashboard exports CSV" do
    sign_in_as users(:admin)
    get sales_report_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", @response.media_type
    assert_match "section,label,count,value_rupees,from,to", response.body
  end

  test "the nav links staff to the sales report under CRM" do
    sign_in_as users(:agent_a)
    get cases_path
    assert_match(%r{/reports/sales}, response.body)
  end

  test "an anonymous visitor is bounced to sign in" do
    get sales_report_path
    assert_redirected_to new_session_path
  end
end
