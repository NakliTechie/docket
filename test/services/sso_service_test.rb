require "test_helper"

class SsoServiceTest < ActiveSupport::TestCase
  teardown do
    SWD.url_builder = URI::HTTPS
    WebFinger.url_builder = URI::HTTPS
    Setting.unset("sso_staff_oidc_issuer")
    Setting.unset("sso_staff_oidc_client_id")
  end

  test "http issuer relaxes discovery url builders to plain http" do
    Setting.set("sso_staff_oidc_issuer", "http://keycloak.internal:8080/realms/test")
    Setting.set("sso_staff_oidc_client_id", "docket-staff")

    Sso.staff_oidc_options

    assert_equal URI::HTTP, SWD.url_builder
    assert_equal URI::HTTP, WebFinger.url_builder
  end

  test "https issuer leaves discovery url builders untouched" do
    Setting.set("sso_staff_oidc_issuer", "https://keycloak.example.com/realms/prod")
    Setting.set("sso_staff_oidc_client_id", "docket-staff")

    Sso.staff_oidc_options

    assert_equal URI::HTTPS, SWD.url_builder
    assert_equal URI::HTTPS, WebFinger.url_builder
  end

  test "form-action origins cover the configured IdPs, default port omitted" do
    Setting.set("sso_staff_oidc_issuer", "http://keycloak.internal:8080/realms/test")
    Setting.set("sso_staff_oidc_client_id", "docket-staff")
    Setting.set("sso_customer_oidc_issuer", "https://login.bank.example/realms/customers")
    Setting.set("sso_customer_oidc_client_id", "docket-customer")

    assert_equal [ "http://keycloak.internal:8080", "https://login.bank.example" ],
                 Sso.idp_form_action_origins
  ensure
    Setting.unset("sso_customer_oidc_issuer")
    Setting.unset("sso_customer_oidc_client_id")
  end

  test "form-action origins empty when no sso configured" do
    assert_equal [], Sso.idp_form_action_origins
  end
end
