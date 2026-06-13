class ApplicationJob < ActiveJob::Base
  # Cases carry a lock_version (optimistic locking). A job that loaded a
  # case which a human then edited mid-flight hits StaleObjectError — just
  # re-run; ActiveJob reloads records by GlobalID, so the retry sees the
  # current row. The per-record work (breach flip, triage) is idempotent.
  retry_on ActiveRecord::StaleObjectError, wait: 1.second, attempts: 3

  # Tenant context for jobs. Request-enqueued jobs already carry their tenant
  # (acts_as_tenant serializes current_tenant into the job and restores it on
  # perform), so we only fill in when none is set — i.e. the recurring scheduler
  # in an ISOLATED deploy, which defaults to the singleton so scoped writes
  # work. Shared-mode per-tenant fan-out for the sweeps lands in Phase C.
  around_perform do |_job, block|
    if ActsAsTenant.current_tenant.nil? && Tenant.isolated_deployment?
      ActsAsTenant.with_tenant(Tenant.primary, &block)
    else
      block.call
    end
  end

  private

  # Run a block once per active tenant, scoped to it. The recurring scheduler
  # sweeps use this so they cover every tenant in a shared deploy (and the single
  # tenant in an isolated one). Jobs enqueued from within (e.g. ConnectorSyncJob)
  # inherit the per-tenant scope via acts_as_tenant's ActiveJob serialization.
  def each_active_tenant(&block)
    Tenant.active.find_each { |tenant| ActsAsTenant.with_tenant(tenant, &block) }
  end
end
