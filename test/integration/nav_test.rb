require "test_helper"

# The top nav is grouped into dropdowns (Cases + CRM / Service desk / Admin),
# role-gated as before.
class NavTest < ActionDispatch::IntegrationTest
  test "an admin sees the grouped dropdowns" do
    sign_in_as users(:admin)
    get cases_path
    assert_response :success
    assert_match "nav-group", response.body
    assert_match ">CRM", response.body
    assert_match "Service desk", response.body
    assert_match ">Admin", response.body
  end

  test "an agent gets CRM but no Admin or Service-desk group" do
    sign_in_as users(:agent_a)
    get cases_path
    assert_response :success
    assert_match ">CRM", response.body
    assert_no_match(%r{/admin/settings}, response.body)
    assert_no_match(%r{/admin/users}, response.body)
  end
end
