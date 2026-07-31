module Tenants
  # Remove pending Solid Queue jobs serialized with this tenant. A worker that
  # already claimed a job is independently stopped by ApplicationJob's
  # suspended-tenant guard, so suspension is fail-closed across the race.
  class Quiesce
    def self.call(tenant:)
      return 0 unless defined?(SolidQueue::Job) && SolidQueue::Job.table_exists?

      gid = tenant.to_global_id.to_s
      escaped = SolidQueue::Job.sanitize_sql_like(gid)
      jobs = SolidQueue::Job.where(finished_at: nil).where("arguments LIKE ?", "%#{escaped}%")
      count = jobs.count
      jobs.destroy_all
      count
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      0
    end
  end
end
