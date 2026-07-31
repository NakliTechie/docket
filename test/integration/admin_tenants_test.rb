require "test_helper"

class AdminTenantsTest < ActionDispatch::IntegrationTest
  setup do
    @original_mode = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    host! "acme.example.com"
    @platform_admin = ActsAsTenant.with_tenant(tenants(:acme)) do
      User.create!(name: "Platform Admin", email_address: "platform-admin@acme.test",
                   password: "long-enough-password", role: :super_admin)
    end
  end

  teardown { Rails.application.config.x.tenancy_mode = @original_mode }

  test "super_admin lists, provisions, and suspends tenants" do
    sign_in_as @platform_admin

    get admin_tenants_path
    assert_response :success
    assert_match tenants(:primary).name, response.body
    assert_match tenants(:acme).name, response.body

    assert_difference "Tenant.count", 1 do
      post admin_tenants_path, params: {
        tenant: { name: "Gamma Corp", subdomain: "gamma", admin_email: "boss@gamma.test" }
      }
    end
    assert_redirected_to admin_tenants_path
    gamma = Tenant.find_by(slug: "gamma")
    assert gamma, "tenant provisioned"
    admin = ActsAsTenant.with_tenant(gamma) { User.find_by(email_address: "boss@gamma.test") }
    assert_equal "client_admin", admin.role

    post suspend_admin_tenant_path(gamma)
    assert gamma.reload.suspended?
    post activate_admin_tenant_path(gamma)
    assert gamma.reload.active?
  end

  test "the primary tenant cannot be suspended" do
    sign_in_as @platform_admin
    post suspend_admin_tenant_path(tenants(:primary))
    assert tenants(:primary).reload.active?, "primary stays active"
  end

  test "non-super_admins cannot reach the platform console" do
    client_admin = ActsAsTenant.with_tenant(tenants(:acme)) do
      User.create!(name: "Acme client admin", email_address: "client-admin@acme.test",
                   password: "long-enough-password", role: :client_admin)
    end
    sign_in_as client_admin
    get admin_tenants_path
    assert_response :forbidden

    finance = ActsAsTenant.with_tenant(tenants(:acme)) do
      User.create!(name: "Acme finance", email_address: "finance-role@acme.test",
                   password: "long-enough-password", role: :finance)
    end
    sign_in_as finance
    get admin_tenants_path
    assert_response :forbidden
  end

  test "an isolated deployment can inspect tenants but cannot provision another" do
    Rails.application.config.x.tenancy_mode = "isolated"
    host! "www.example.com"
    sign_in_as users(:super_admin)

    get admin_tenants_path
    assert_response :success
    assert_no_match I18n.t("admin.tenants.index.provision"), response.body

    get new_admin_tenant_path
    assert_response :forbidden
    assert_no_difference "Tenant.count" do
      post admin_tenants_path, params: { tenant: { name: "Orphan", subdomain: "orphan" } }
    end
    assert_response :forbidden
  end
end
