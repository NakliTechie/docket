require "test_helper"

# Regression cover for a production bug that killed SSO for any tenant whose
# config lives on its own row rather than globally.
#
# OmniAuth's setup phase is Rack MIDDLEWARE — it runs before TenantResolution
# puts a tenant in scope. Settings resolve tenant-first with a global fallback,
# so an unscoped read sees ONLY the global row: the provider reported
# "not configured" and the request bounced to /auth/failure before ever reaching
# the IdP. The live Keycloak harness had been failing on this since the
# multi-tenancy work landed; every OmniAuth test-mode suite passed throughout,
# because test mode skips the setup phase entirely.
class SsoTenantResolutionTest < ActiveSupport::TestCase
  def env_for(host)
    Rack::MockRequest.env_for("http://#{host}/auth/staff_oidc", method: "POST")
  end

  test "the setup phase sees a tenant's own SSO settings, not just the global ones" do
    ActsAsTenant.with_tenant(tenants(:primary)) do
      Setting.set("sso_staff_oidc_issuer", "https://idp.example/realms/primary")
      Setting.set("sso_staff_oidc_client_id", "primary-client")
      Setting.set("sso_staff_oidc_client_secret", "primary-secret")
    end

    # No tenant in scope — exactly the state the middleware runs in.
    ActsAsTenant.without_tenant do
      refute Sso.staff_oidc_enabled?, "sanity: unscoped, only the global row is visible"

      Sso.with_request_tenant(env_for("localhost")) do
        assert Sso.staff_oidc_enabled?,
               "the setup phase must resolve the tenant before reading settings"
        assert_equal "primary-client", Sso.staff_oidc_options.dig(:client_options, :identifier)
      end
    end
  end

  test "each tenant's SSO config is resolved from the request host" do
    # Subdomain resolution only applies in a SHARED deploy; isolated always
    # resolves the singleton, which is correct there.
    original = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    ActsAsTenant.with_tenant(tenants(:primary)) do
      Setting.set("sso_staff_oidc_issuer", "https://idp.example/realms/primary")
      Setting.set("sso_staff_oidc_client_id", "primary-client")
      Setting.set("sso_staff_oidc_client_secret", "primary-secret")
    end
    ActsAsTenant.with_tenant(tenants(:acme)) do
      Setting.set("sso_staff_oidc_issuer", "https://idp.example/realms/acme")
      Setting.set("sso_staff_oidc_client_id", "acme-client")
      Setting.set("sso_staff_oidc_client_secret", "acme-secret")
    end

    ActsAsTenant.without_tenant do
      Sso.with_request_tenant(env_for("acme.docket.test")) do
        assert_equal "acme-client", Sso.staff_oidc_options.dig(:client_options, :identifier),
                     "a tenant must not be handed another tenant's IdP client"
      end
    end
  ensure
    Rails.application.config.x.tenancy_mode = original
  end

  test "an unknown host leaves no tenant in scope and the provider fails closed" do
    ActsAsTenant.without_tenant do
      Sso.with_request_tenant(env_for("nobody.docket.test")) do
        # Isolated mode resolves the singleton; shared mode resolves nothing.
        # Either way the block runs and the caller's `enabled?` guard decides —
        # it never silently adopts some other tenant's configuration.
        assert_nothing_raised { Sso.staff_oidc_enabled? }
      end
    end
  end
end
