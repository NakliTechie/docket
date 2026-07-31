require "application_system_test_case"

class TenantSuspensionTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "an isolated suspended workspace renders only its branded outage page" do
    tenant = tenants(:primary)
    Setting.set("brand_name", "Northwind Support")
    tenant.suspended!

    visit root_path

    assert_equal 503, page.status_code
    assert_text "Northwind Support"
    assert_text I18n.t("errors.tenant_suspended.title")
    assert_no_selector ".app-nav"
  ensure
    tenant&.update_column(:status, Tenant.statuses.fetch("active"))
  end
end
