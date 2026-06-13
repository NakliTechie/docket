require "test_helper"

class Tenants::ProvisionerTest < ActiveSupport::TestCase
  test "provisions a tenant with its own defaults and a client_admin" do
    result = Tenants::Provisioner.call(name: "Beta Corp", subdomain: "Beta",
                                       admin_email: "Boss@Beta.test")
    tenant = result.tenant

    assert_equal "beta", tenant.slug, "subdomain/slug normalized to lowercase"
    assert_equal "beta", tenant.subdomain
    assert_equal "client_admin", result.admin.role, "the tenant admin is a per-tenant client_admin"
    assert result.admin_password.present?

    queue_id = ActsAsTenant.with_tenant(tenant) do
      assert Pipeline.exists?, "new tenant gets a default pipeline"
      assert SlaPolicy.exists?, "new tenant gets a default SLA"
      queue = CaseQueue.find_by(name: "General")
      assert queue, "new tenant gets a default queue"
      assert_equal queue.id, Setting.get("default_queue_id"), "default_queue_id is the tenant's own"
      queue.id
    end

    # The provisioned queue is invisible to other tenants.
    ActsAsTenant.with_tenant(tenants(:primary)) do
      refute CaseQueue.exists?(queue_id), "beta's queue must not leak into primary"
    end
  end
end
