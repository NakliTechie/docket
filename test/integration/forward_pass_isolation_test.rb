require "test_helper"

# Forward pass 2026-06-13, Batch A: shared-mode tenant isolation on the audit,
# activity, security-event and CORS read surfaces. super_admin (and isolated
# deployments) keep the global view; every other role is scoped to its tenant.
class ForwardPassIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @orig_mode = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    @acme = tenants(:acme)
    @primary = tenants(:primary)
    @acme_admin = ActsAsTenant.with_tenant(@acme) do
      User.create!(name: "Acme Admin", email_address: "admin@acme.test", password: "password1234", role: :client_admin)
    end
  end

  teardown { Rails.application.config.x.tenancy_mode = @orig_mode }

  # --- C1: AuditEntry read scoping ---

  test "AuditEntry.visible_to scopes to the tenant except super_admin / isolated" do
    acme_entry = ActsAsTenant.with_tenant(@acme) { AuditEntry.append!(action: "acme.evt", auditable: @acme_admin) }
    primary_entry = ActsAsTenant.with_tenant(@primary) { AuditEntry.append!(action: "primary.evt", auditable: users(:admin)) }

    ActsAsTenant.with_tenant(@acme) do
      visible = AuditEntry.visible_to(@acme_admin)
      assert_includes visible, acme_entry
      refute_includes visible, primary_entry, "client_admin must not see another tenant's audit entries"

      super_admin = User.create!(name: "Platform", email_address: "sa@acme.test", password: "password1234", role: :super_admin)
      assert_includes AuditEntry.visible_to(super_admin), primary_entry, "super_admin keeps the global view"
    end

    Rails.application.config.x.tenancy_mode = "isolated"
    ActsAsTenant.with_tenant(@primary) do
      assert_includes AuditEntry.visible_to(@acme_admin), primary_entry, "isolated → no tenant filtering"
    end
  end

  test "the API audit log only returns the host tenant's entries" do
    acme_entry = ActsAsTenant.with_tenant(@acme) { AuditEntry.append!(action: "acme.secret", auditable: @acme_admin) }
    ActsAsTenant.with_tenant(@primary) { AuditEntry.append!(action: "primary.secret", auditable: users(:admin)) }
    token = ActsAsTenant.with_tenant(@acme) { ApiToken.create!(user: @acme_admin, name: "cli").raw_token }

    host! "acme.docket.app"
    get "/api/v1/audit/entries", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    body = response.body
    assert_includes body, "acme.secret"
    refute_includes body, "primary.secret", "the API audit list leaked another tenant's entries"
  end

  test "global chain verification is denied to a non-super_admin tenant in shared mode" do
    token = ActsAsTenant.with_tenant(@acme) { ApiToken.create!(user: @acme_admin, name: "cli").raw_token }
    host! "acme.docket.app"
    get "/api/v1/audit/verification", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :forbidden
  end

  # --- C1: ActivityReport scoping ---

  test "ActivityReport audit-derived metrics are tenant-scoped for a non-super_admin" do
    range_day = Date.current
    ActsAsTenant.with_tenant(@acme) { AuditEntry.append!(action: "user.login", auditable: @acme_admin, metadata: { "ip" => "9.9.9.9" }) }
    ActsAsTenant.with_tenant(@primary) { AuditEntry.append!(action: "user.login", auditable: users(:admin), metadata: { "ip" => "8.8.8.8" }) }

    ActsAsTenant.with_tenant(@acme) do
      report = ActivityReport.new(from: range_day, to: range_day, viewer: @acme_admin)
      ips = report.logins.map { |e| e.metadata&.dig("ip") }
      assert_includes ips, "9.9.9.9"
      refute_includes ips, "8.8.8.8", "another tenant's login IP leaked into the activity report"
    end
  end

  # --- H1: SecurityEvent read scoping ---

  test "SecurityEvent stamps the tenant and visible_to scopes it" do
    acme_evt = ActsAsTenant.with_tenant(@acme) { SecurityEvent.record("login_failed", email: "x@acme.test", ip_address: "1.2.3.4") }
    primary_evt = ActsAsTenant.with_tenant(@primary) { SecurityEvent.record("login_failed", email: "y@primary.test", ip_address: "5.6.7.8") }
    assert_equal @acme.id, acme_evt.tenant_id

    ActsAsTenant.with_tenant(@acme) do
      visible = SecurityEvent.visible_to(@acme_admin)
      assert_includes visible, acme_evt
      refute_includes visible, primary_evt, "another tenant's failed-login record leaked"
    end
  end

  # --- M1: per-tenant CORS ---

  test "the CORS allowlist is resolved per-tenant from the host" do
    ActsAsTenant.with_tenant(@acme) { Setting.set("cors_allowed_origins", "https://app.acme.test") }
    ActsAsTenant.with_tenant(@primary) { Setting.set("cors_allowed_origins", "https://app.primary.test") }

    host! "acme.docket.app"
    get "/api/v1/openapi.json", headers: { "HTTP_ORIGIN" => "https://app.acme.test" }
    assert_equal "https://app.acme.test", response.headers["Access-Control-Allow-Origin"], "acme's own origin should be allowed on its host"

    get "/api/v1/openapi.json", headers: { "HTTP_ORIGIN" => "https://app.primary.test" }
    assert_nil response.headers["Access-Control-Allow-Origin"], "another tenant's allowed origin must not be honored on acme's host"
  end
end
