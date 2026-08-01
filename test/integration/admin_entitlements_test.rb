require "test_helper"

# The platform console's packaging screen. Same screen serves both SKUs: in a
# shared deploy it packages a customer, in a dedicated deploy it's the operator's
# own switchboard on the primary tenant.
class AdminEntitlementsTest < ActionDispatch::IntegrationTest
  test "the platform tier can see and change a tenant's modules" do
    sign_in_as users(:admin) # super_admin holds tenant:manage
    tenant = tenants(:acme)

    get entitlements_admin_tenant_path(tenant)
    assert_response :success

    patch entitlements_admin_tenant_path(tenant), params: { features: %w[service_desk service_desk.kb] }
    assert_redirected_to entitlements_admin_tenant_path(tenant)

    tenant.reload
    assert tenant.feature?("service_desk")
    assert tenant.feature?("service_desk.kb")
    refute tenant.feature?("crm"), "a module absent from the submitted set is off"
    refute tenant.feature?("work")
  end

  test "submitting no features turns everything off" do
    sign_in_as users(:admin)
    tenant = tenants(:acme)

    patch entitlements_admin_tenant_path(tenant), params: {}
    tenant.reload
    Features::KEYS.each { |key| refute tenant.feature?(key), "#{key} should be off" }
  end

  test "a preset applies as a set" do
    sign_in_as users(:admin)
    tenant = tenants(:acme)

    patch entitlements_admin_tenant_path(tenant), params: { preset: "service_only" }
    tenant.reload
    assert tenant.feature?("service_desk")
    refute tenant.feature?("crm")
    refute tenant.feature?("work")
  end

  test "an unknown preset is rejected without changing anything" do
    sign_in_as users(:admin)
    tenant = tenants(:acme)
    before = tenant.entitlements.dup

    patch entitlements_admin_tenant_path(tenant), params: { preset: "enterprise_plus" }
    assert_equal before, tenant.reload.entitlements
  end

  test "a client_admin cannot repackage their own tenant" do
    sign_in_as users(:client_admin)

    get entitlements_admin_tenant_path(tenants(:primary))
    assert_response :forbidden

    patch entitlements_admin_tenant_path(tenants(:primary)), params: { features: [] }
    assert_response :forbidden
    assert tenants(:primary).reload.feature?("crm"), "nothing changed"
  end

  test "entitlement changes land in the audit chain" do
    sign_in_as users(:admin)
    tenant = tenants(:acme)

    assert_difference "AuditEntry.count", 1 do
      patch entitlements_admin_tenant_path(tenant), params: { features: %w[service_desk] }
    end
  end

  test "provisioning takes a preset; the default is every module" do
    original = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    begin
      full = Tenants::Provisioner.call(name: "Full Co", subdomain: "fullco").tenant
      assert full.feature?("crm")
      assert full.feature?("work")

      desk = Tenants::Provisioner.call(name: "Desk Co", subdomain: "deskco", preset: "service_only").tenant
      assert desk.feature?("service_desk")
      refute desk.feature?("crm")
    ensure
      Rails.application.config.x.tenancy_mode = original
    end
  end
end
