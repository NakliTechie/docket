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

  # The invocation:review tier (client_admin) is the human-of-record for
  # `of_record` agent actions, so the approval queue must be reachable from
  # their nav via the Service-desk group.
  test "a client_admin reaches the agent-actions approval queue via Service desk" do
    sign_in_as users(:client_admin)
    get cases_path
    assert_response :success
    assert_match "Service desk", response.body
    assert_match(%r{/admin/connector_invocations}, response.body)
  end

  test "a role without invocation:review cannot see the approval queue" do
    sign_in_as users(:customer_service)
    get cases_path
    assert_response :success
    assert_no_match(%r{/admin/connector_invocations}, response.body)
  end
end
