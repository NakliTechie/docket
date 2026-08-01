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
  # work. Shared sweeps fan out explicitly through each_tenant_with_feature.
  around_perform do |_job, block|
    tenant = ActsAsTenant.current_tenant
    if tenant&.suspended?
      Rails.logger.info("discarded #{self.class.name} for suspended tenant #{tenant.id}")
    elsif tenant.nil? && Tenant.isolated_deployment?
      ActsAsTenant.with_tenant(Tenant.primary, &block)
    else
      block.call
    end
  end

  # A recurring sweep that stops running is silent — the handoff says so
  # outright ("if they don't run, nothing tells you"). Each sweep stamps its own
  # completion so /healthz can answer "when did this last work?" without a new
  # dependency. Global (not tenant-scoped): it is about the SCHEDULER, and the
  # scheduler is per deployment.
  def record_sweep_success!(name = self.class.name)
    ActsAsTenant.without_tenant do
      key = "job_last_success.#{name}"
      now = Time.current.iso8601
      # Written WITHOUT the audit callbacks on purpose. This is a heartbeat, not
      # a business action: at five sweeps on five-minute-to-hourly schedules it
      # would append well over a thousand entries a day to the hash chain and
      # dilute the thing the chain exists for. update_columns/insert_all skip
      # Audited; the value is operational, not accountable.
      existing = Setting.where(tenant_id: nil, key: key).first
      if existing
        existing.update_columns(value: now, updated_at: Time.current)
      else
        Setting.insert_all([ { tenant_id: nil, key: key, value: now,
                               created_at: Time.current, updated_at: Time.current } ])
      end
    end
  rescue StandardError => e
    # Never let bookkeeping fail the sweep it is reporting on.
    Rails.logger.warn("could not record sweep success for #{name}: #{e.message}")
  end

  private

  # Run a block once per active tenant, scoped to it. The recurring scheduler
  # sweeps use this so they cover every tenant in a shared deploy (and the single
  # tenant in an isolated one). Jobs enqueued from within (e.g. ConnectorSyncJob)
  # inherit the per-tenant scope via acts_as_tenant's ActiveJob serialization.
  def each_active_tenant(&block)
    Tenant.active.find_each { |tenant| ActsAsTenant.with_tenant(tenant, &block) }
  end

  # The entitlement-aware fan-out every recurring sweep must use. A sweep that
  # ignores packaging keeps a module RUNNING for a tenant that doesn't have it —
  # and these sweeps have outward, customer-visible effects (sequence email,
  # SLA-breach webhooks, autonomous decisions). "The console hides it" is not
  # containment when cron still fires it.
  def each_tenant_with_feature(key, &block)
    Tenant.active.find_each do |tenant|
      next unless tenant.feature?(key)

      ActsAsTenant.with_tenant(tenant, &block)
    end
  end
end
