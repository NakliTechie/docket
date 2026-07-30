require "test_helper"

# The top nav is grouped by user task and remains role-gated.
class NavTest < ActionDispatch::IntegrationTest
  test "an admin sees the grouped dropdowns" do
    sign_in_as users(:admin)
    get cases_path
    assert_response :success
    assert_match "nav-group", response.body
    assert_match ">Customers", response.body
    assert_match ">Sales", response.body
    assert_match "Knowledge &amp; automation", response.body
    assert_match ">Administration", response.body
    assert_match "API access", response.body
  end

  test "a customer-service user gets customer work without administration" do
    sign_in_as users(:agent_a)
    get cases_path
    assert_response :success
    assert_match ">Customers", response.body
    assert_match ">Inbox", response.body
    assert_no_match ">Sales", response.body
    assert_no_match(%r{/admin/settings}, response.body)
    assert_no_match(%r{/admin/users}, response.body)
  end

  # The invocation:review tier (client_admin) is the human-of-record for
  # `of_record` agent actions, so the approval queue remains reachable.
  test "a client_admin reaches the agent-actions approval queue via automation" do
    sign_in_as users(:client_admin)
    get cases_path
    assert_response :success
    assert_match "Knowledge &amp; automation", response.body
    assert_match(%r{/admin/connector_invocations}, response.body)
  end

  test "a role without invocation:review cannot see the approval queue" do
    sign_in_as users(:customer_service)
    get cases_path
    assert_response :success
    assert_no_match(%r{/admin/connector_invocations}, response.body)
  end
end
