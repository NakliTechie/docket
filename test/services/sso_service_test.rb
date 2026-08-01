require "test_helper"

class SsoServiceTest < ActiveSupport::TestCase
  teardown do
    Setting.unset("sso_staff_oidc_issuer")
    Setting.unset("sso_staff_oidc_client_id")
    Setting.unset("sso_staff_jit_domains")
  end

  test "discovery preserves each issuer scheme without changing process globals" do
    http = OpenIDConnect::Discovery::Provider::Config::Resource.new(
      URI("http://keycloak.internal:8080/realms/test")
    )
    https = OpenIDConnect::Discovery::Provider::Config::Resource.new(
      URI("https://login.example/tenant")
    )

    assert_equal "http://keycloak.internal:8080/realms/test/.well-known/openid-configuration",
                 http.endpoint.to_s
    assert_equal "https://login.example/tenant/.well-known/openid-configuration",
                 https.endpoint.to_s
    assert_equal URI::HTTPS, SWD.url_builder
    assert_equal URI::HTTPS, WebFinger.url_builder

    assert_equal "http", WebFinger::Request.new("http://keycloak.internal:8080")
                                           .send(:endpoint).scheme
    assert_equal "https", WebFinger::Request.new("https://login.example")
                                            .send(:endpoint).scheme
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

  test "staff JIT domains are normalized and exact-match only" do
    Setting.set("sso_staff_jit_domains", " @Example.COM, subsidiary.example.com invalid/domain ")
    assert_equal %w[example.com subsidiary.example.com], Sso.staff_jit_domains
    assert Sso.staff_jit_allowed?("person@example.com")
    refute Sso.staff_jit_allowed?("person@notexample.com")
    refute Sso.staff_jit_allowed?("person@deep.example.com")
  end
end
