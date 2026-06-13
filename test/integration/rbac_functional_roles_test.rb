require "test_helper"

# End-to-end checks that the new functional roles enforce the separation of
# duties a bank/PSE buyer expects — finance is walled off from platform
# plumbing but sees the dashboards; technical operates connectors but can't
# manage them; the roles matrix is visible to user-managers only.
class RbacFunctionalRolesTest < ActionDispatch::IntegrationTest
  test "finance sees the operational dashboard but is walled off from platform plumbing" do
    sign_in_as users(:finance)

    get dashboard_path
    assert_response :success

    get admin_settings_path
    assert_response :forbidden

    get admin_connectors_path
    assert_response :forbidden

    # No case:write — cannot create cases.
    post cases_path, params: { case: { subject: "x", description: "y", priority: "normal" } }
    assert_response :forbidden
  end

  test "technical may view/operate connectors but not manage them" do
    sign_in_as users(:technical)

    get admin_connectors_path
    assert_response :success

    get new_admin_connector_path
    assert_response :forbidden
  end

  test "sales works the CRM but cannot see the operational dashboard" do
    sign_in_as users(:sales)

    get leads_path
    assert_response :success

    get dashboard_path
    assert_response :forbidden
  end

  test "the roles matrix page is visible to user-managers and renders permissions" do
    sign_in_as users(:client_admin)
    get admin_roles_path
    assert_response :success
    assert_match "case:read", response.body
    assert_match I18n.t("users.enum.role.finance"), response.body

    sign_in_as users(:finance)
    get admin_roles_path
    assert_response :forbidden
  end
end
