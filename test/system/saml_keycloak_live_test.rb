require "application_system_test_case"
require "net/http"
require "rexml/document"

# Live SAML flow against a containerised Keycloak (handoff §5A / G3, D2).
# The SAML sibling of sso_keycloak_live_test.rb: drives the real browser
# through a SAML AuthnRequest → Keycloak login → signed assertion POST to the
# ACS → JIT-provisioned staff session, and proves role mapping still promotes a
# docket-admins member to super_admin over SAML.
#
# Run via bin/keycloak-test or CI's keycloak-sso job:
#   KEYCLOAK_URL=http://localhost:8080 bin/rails test test/system/saml_keycloak_live_test.rb
# Skipped when KEYCLOAK_URL is unset so the default suite needs no containers.
class SamlKeycloakLiveTest < ApplicationSystemTestCase
  KEYCLOAK_URL = ENV["KEYCLOAK_URL"]
  REALM = "docket-test"

  setup do
    skip "KEYCLOAK_URL not set — Keycloak live test skipped" if KEYCLOAK_URL.blank?
    skip "No browser available" unless self.class.browser_path

    Capybara.server_host = "localhost"
    Capybara.server_port = 3001
    base = "http://localhost:3001"

    # SP entity id MUST equal the SAML client's clientId in the realm fixture —
    # Keycloak matches the AuthnRequest Issuer against clientId.
    sp_entity_id = "#{base}/auth/staff_saml/metadata"

    Setting.set("app_base_url", base)
    Setting.set("sso_staff_saml_idp_sso_url", "#{KEYCLOAK_URL}/realms/#{REALM}/protocol/saml")
    Setting.set("sso_staff_saml_idp_cert", fetch_idp_signing_cert)
    Setting.set("sso_staff_saml_sp_entity_id", sp_entity_id)
    Setting.set("sso_staff_jit_domains", "example.com")
    Setting.set("sso_staff_role_claim", "groups")
    Setting.set("sso_staff_role_mapping", { "docket-admins" => "super_admin" }.to_json)
  end

  test "staff saml login against keycloak provisions a super_admin via role mapping" do
    visit new_session_path
    click_button I18n.t("sessions.new.sso_saml")

    # Keycloak login form (same realm/user as the OIDC live test).
    fill_in "username", with: "staff.user", wait: 10
    fill_in "password", with: "staffpass"
    click_button "Sign In"

    # A super_admin lands on the dashboard; assert on the signed-in header's
    # role badge so this proves the SAML assertion round-trip + role mapping
    # without coupling to whichever surface is the landing page.
    assert_text I18n.t("users.enum.role.super_admin"), wait: 10
    user = User.find_by(email_address: "staff.sso@example.com")
    assert_equal "super_admin", user.role
  end

  private

  # Read the IdP signing certificate from Keycloak's live SAML descriptor
  # instead of pinning a static cert: the container regenerates realm keys on
  # each boot, so a hardcoded cert would break the signature check. Mirrors how
  # OIDC discovery resolves keys dynamically.
  def fetch_idp_signing_cert
    url = "#{KEYCLOAK_URL}/realms/#{REALM}/protocol/saml/descriptor"
    xml = Net::HTTP.get(URI(url))
    doc = REXML::Document.new(xml)
    node = REXML::XPath.first(
      doc,
      "//*[local-name()='KeyDescriptor'][@use='signing']//*[local-name()='X509Certificate']"
    )
    raise "No signing certificate in SAML descriptor at #{url}" if node.nil?

    b64 = node.text.to_s.gsub(/\s+/, "")
    "-----BEGIN CERTIFICATE-----\n#{b64.scan(/.{1,64}/).join("\n")}\n-----END CERTIFICATE-----\n"
  end
end
