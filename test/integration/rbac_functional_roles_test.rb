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
    assert_select "a[href='#{admin_connectors_path}']", count: 0
    assert_select "a[href='#{admin_connector_invocations_path}']", count: 0
    assert_select "form[action='#{run_decisions_path}']", count: 0

    get admin_settings_path
    assert_response :forbidden

    get admin_connectors_path
    assert_response :forbidden

    # No case:write — cannot create cases.
    post cases_path, params: { case: { subject: "x", description: "y", priority: "normal" } }
    assert_response :forbidden
  end

  test "technical may view/operate connectors but not manage them" do
    connector = Connector.create!(
      name: "RBAC walkthrough connector",
      provider: "http_json",
      target: "contacts",
      config: { "endpoint_url" => "https://api.example.test/contacts" },
      field_mapping: { "external_id" => "id" }
    )
    sign_in_as users(:technical)

    get dashboard_path
    assert_response :success
    assert_select "a[href='#{admin_connectors_path}']",
      text: I18n.t("dashboards.index.manage_connectors"), count: 1
    assert_select "a[href='#{admin_connector_invocations_path}']", count: 0
    assert_select "form[action='#{run_decisions_path}']", count: 0
    assert_select "a[href='#{admin_webhook_endpoints_path}']", count: 1

    get admin_connectors_path
    assert_response :success
    assert_select "a[href='#{admin_shared_credentials_path}']", count: 0
    assert_select "a[href^='#{new_admin_connector_path}']", count: 0

    get admin_connector_path(connector)
    assert_response :success
    assert_select "form[action='#{sync_admin_connector_path(connector)}']", count: 1
    assert_select "form[action='#{pause_admin_connector_path(connector)}']", count: 1
    assert_select "a[href='#{edit_admin_connector_path(connector)}']", count: 0
    assert_select "form[action='#{admin_connector_path(connector)}']", count: 0

    post pause_admin_connector_path(connector)
    assert_redirected_to admin_connector_path(connector)
    assert connector.reload.status_paused?

    post resume_admin_connector_path(connector)
    assert_redirected_to admin_connector_path(connector)
    assert connector.reload.status_active?

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

  test "customer service supervisor manages desk configuration without platform authority" do
    sign_in_as users(:customer_service_supervisor)

    get dashboard_path
    assert_response :success
    get new_case_queue_path
    assert_response :success
    get new_routing_rule_path
    assert_response :success
    get new_sla_policy_path
    assert_response :success
    get new_macro_path
    assert_response :success
    get admin_settings_path
    assert_response :forbidden
  end

  test "decision reviewer reaches approval and decision surfaces without operational writes" do
    sign_in_as users(:decision_reviewer)

    get admin_approval_requests_path
    assert_response :success
    get dashboard_path
    assert_response :success
    assert_select "form[action='#{run_decisions_path}']", count: 1
    post cases_path, params: { case: { subject: "x", description: "y", priority: "normal" } }
    assert_response :forbidden
  end

  test "knowledge manager owns article lifecycle without user administration" do
    sign_in_as users(:knowledge_manager)

    get admin_reference_docs_path
    assert_response :success
    get new_admin_reference_doc_path
    assert_response :success
    get admin_users_path
    assert_response :forbidden
  end

  test "auditor reads oversight surfaces and exports without mutation authority" do
    sign_in_as users(:auditor)

    get admin_activity_path
    assert_response :success
    get dashboard_path(format: :csv)
    assert_response :success
    post cases_path, params: { case: { subject: "x", description: "y", priority: "normal" } }
    assert_response :forbidden
  end

  test "client admin sees review controls but not connector management" do
    sign_in_as users(:client_admin)

    get dashboard_path
    assert_response :success
    assert_select "a[href='#{admin_connectors_path}']", count: 0
    assert_select "a[href='#{admin_connector_invocations_path}']",
      text: I18n.t("dashboards.index.view_agent_actions"), count: 1
    assert_select "form[action='#{run_decisions_path}']", count: 1
    assert_select "a[href='#{admin_service_accounts_path}']", count: 0
    assert_select "a[href='#{admin_settings_path}']", count: 0
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
