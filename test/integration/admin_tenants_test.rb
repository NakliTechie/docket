require "test_helper"

class AdminTenantsTest < ActionDispatch::IntegrationTest
  test "super_admin lists, provisions, and suspends tenants" do
    sign_in_as users(:super_admin)

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
    sign_in_as users(:super_admin)
    post suspend_admin_tenant_path(tenants(:primary))
    assert tenants(:primary).reload.active?, "primary stays active"
  end

  test "non-super_admins cannot reach the platform console" do
    sign_in_as users(:client_admin)
    get admin_tenants_path
    assert_response :forbidden

    sign_in_as users(:finance)
    get admin_tenants_path
    assert_response :forbidden
  end
end
