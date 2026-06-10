require "application_system_test_case"

# Live OIDC flows against a containerised Keycloak (handoff §5A / G3).
# Run via bin/keycloak-test or CI's keycloak job:
#   KEYCLOAK_URL=http://localhost:8080 bin/rails test test/system/sso_keycloak_live_test.rb
# Skipped when KEYCLOAK_URL is unset so the default suite needs no
# containers.
class SsoKeycloakLiveTest < ApplicationSystemTestCase
  KEYCLOAK_URL = ENV["KEYCLOAK_URL"]

  setup do
    skip "KEYCLOAK_URL not set — Keycloak live test skipped" if KEYCLOAK_URL.blank?
    skip "No browser available" unless self.class.browser_path

    Capybara.server_host = "localhost"
    Capybara.server_port = 3001
    base = "http://localhost:3001"
    issuer = "#{KEYCLOAK_URL}/realms/docket-test"

    Setting.set("app_base_url", base)
    Setting.set("sso_staff_oidc_issuer", issuer)
    Setting.set("sso_staff_oidc_client_id", "docket-staff")
    Setting.set("sso_staff_oidc_client_secret", "staff-client-secret")
    Setting.set("sso_staff_role_claim", "groups")
    Setting.set("sso_staff_role_mapping", { "docket-admins" => "admin" }.to_json)
    Setting.set("sso_customer_oidc_issuer", issuer)
    Setting.set("sso_customer_oidc_client_id", "docket-customer")
    Setting.set("sso_customer_oidc_client_secret", "customer-client-secret")
    Setting.set("sso_customer_external_id_claim", "cif")
  end

  test "staff oidc login against keycloak provisions an admin via role mapping" do
    visit new_session_path
    click_button I18n.t("sessions.new.sso_oidc")

    # Keycloak login form
    fill_in "username", with: "staff.user"
    fill_in "password", with: "staffpass"
    click_button "Sign In"

    assert_text I18n.t("cases.index.title")
    user = User.find_by(email_address: "staff.sso@example.com")
    assert_equal "admin", user.role
  end

  test "customer oidc login against keycloak maps cif and stays portal-only" do
    visit portal_root_path
    click_button I18n.t("portal.nav.customer_sign_in")

    fill_in "username", with: "customer.user"
    fill_in "password", with: "customerpass"
    click_button "Sign In"

    assert_text I18n.t("portal.my_cases.index.title")
    assert Contact.exists?(external_id: "CIF555123")

    visit cases_path
    assert_current_path new_session_path
  end
end
