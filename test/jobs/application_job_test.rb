require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  class TenantProbeJob < ApplicationJob
    class_attribute :performed, default: false

    def perform
      self.class.performed = true
    end
  end

  test "jobs do not execute inside a suspended tenant context" do
    tenant = tenants(:acme)
    tenant.suspended!
    TenantProbeJob.performed = false

    ActsAsTenant.with_tenant(tenant) { TenantProbeJob.perform_now }

    assert_not TenantProbeJob.performed
  ensure
    tenant&.active!
    TenantProbeJob.performed = false
  end

  test "jobs continue to execute for an active tenant" do
    TenantProbeJob.performed = false

    ActsAsTenant.with_tenant(tenants(:acme)) { TenantProbeJob.perform_now }

    assert TenantProbeJob.performed
  ensure
    TenantProbeJob.performed = false
  end
end
