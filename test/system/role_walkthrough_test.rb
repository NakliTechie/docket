require "application_system_test_case"

# A browser-level contract for every staff role. Request tests still own the
# exhaustive permission matrix; these checks make sure each role's real
# navigation, primary working surface, and a representative forbidden boundary
# agree with that matrix.
class RoleWalkthroughTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "readonly can inspect cases without mutation controls" do
    sign_in_with_form users(:readonly)

    visit cases_path
    assert_selector "a[href='#{case_path(cases(:pension_case))}']"
    assert_no_selector "a[href='#{new_case_path}']"

    visit case_path(cases(:pension_case))
    assert_text cases(:pension_case).subject
    assert_no_selector "textarea[name='message[body]']"

    assert_forbidden admin_settings_path
  end

  test "finance reaches reporting but not operational or platform writes" do
    sign_in_with_form users(:finance)

    visit dashboard_path
    assert_selector "a[href='#{dashboard_path}']"
    assert_no_selector "a[href='#{admin_connectors_path}']"
    assert_no_selector "a[href='#{admin_connector_invocations_path}']"
    assert_no_selector "form[action='#{run_decisions_path}']"

    assert_forbidden admin_connectors_path
  end

  test "sales works leads without gaining the operational dashboard" do
    sign_in_with_form users(:sales)

    visit leads_path
    assert_text I18n.t("leads.index.title")
    assert_selector "a[href='#{new_lead_path}']"

    assert_forbidden dashboard_path
  end

  test "customer service works a case without administration access" do
    sign_in_with_form users(:customer_service)

    visit case_path(cases(:pension_case))
    assert_text cases(:pension_case).subject
    assert_selector "textarea[name='message[body]']"
    assert_no_selector "a[href='#{admin_users_path}']"

    assert_forbidden admin_users_path
  end

  test "technical operates a connector without management controls" do
    connector = Connector.create!(
      name: "Browser walkthrough connector",
      provider: "http_json",
      target: "contacts",
      config: { "endpoint_url" => "https://api.example.test/contacts" },
      field_mapping: { "external_id" => "id" }
    )
    sign_in_with_form users(:technical)

    visit dashboard_path
    assert_selector "a[href='#{admin_connectors_path}']"
    assert_selector "a[href='#{admin_webhook_endpoints_path}']"

    visit admin_connector_path(connector)
    assert_button I18n.t("admin.connectors.show.sync_now")
    assert_button I18n.t("admin.connectors.show.pause")
    assert_no_selector "a[href='#{edit_admin_connector_path(connector)}']"

    click_button I18n.t("admin.connectors.show.pause")
    assert_button I18n.t("admin.connectors.show.resume")
    click_button I18n.t("admin.connectors.show.resume")
    assert_button I18n.t("admin.connectors.show.pause")

    assert_forbidden new_admin_connector_path
  end

  test "client admin reviews agent actions without platform settings" do
    sign_in_with_form users(:client_admin)

    visit admin_connector_invocations_path
    assert_text I18n.t("admin.connector_invocations.index.title")

    visit admin_users_path
    assert_selector "a[href='#{admin_roles_path}']"
    assert_no_selector "a[href='#{admin_settings_path}']"

    assert_forbidden admin_settings_path
  end

  test "super admin reaches platform configuration" do
    sign_in_with_form users(:super_admin)

    visit admin_settings_path
    assert_text I18n.t("admin.settings.show.title")
    assert_selector "a[href='#{admin_tenants_path}']"
    assert_selector "a[href='#{admin_service_accounts_path}']"
    assert_selector "a[href='#{admin_connectors_path}']"
  end

  private

  def assert_forbidden(path)
    visit path
    assert_text I18n.t("errors.forbidden.title")
  end
end
