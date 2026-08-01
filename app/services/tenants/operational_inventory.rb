require "base64"

module Tenants
  # Tenant-attributable residue in the production queue/cable databases. Cache
  # is intentionally absent: Docket's only Rails.cache keys are global audit-
  # chain verification results and contain no tenant business payload.
  class OperationalInventory
    def initialize(tenant_or_id)
      @tenant_id = Integer(tenant_or_id.respond_to?(:id) ? tenant_or_id.id : tenant_or_id)
    end

    def rows
      @rows ||= { "solid_queue_jobs" => queue_jobs, "solid_queue_failed_executions" => queue_failures,
                  "solid_cable_messages" => cable_messages }.transform_values do |records|
        records.map { |record| json_safe(record.attributes) }
      end
    end

    def counts
      rows.transform_values(&:size).select { |_, count| count.positive? }
    end

    def purge!
      job_ids = purge_queue_jobs
      purge_cable_messages
      counts_after = self.class.new(@tenant_id).counts
      raise "operational tenant residue remains: #{counts_after.inspect}" if counts_after.any?

      job_ids.size
    end

    private

    def tenant
      @tenant ||= Tenant.find_by(id: @tenant_id)
    end

    def queue_job_relation
      return unless defined?(SolidQueue::Job) && SolidQueue::Job.table_exists?

      gid = tenant ? tenant.to_global_id.to_s : "gid://docket/Tenant/#{@tenant_id}"
      escaped = SolidQueue::Job.sanitize_sql_like(gid)
      SolidQueue::Job.where("arguments LIKE ?", "%#{escaped}%")
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      nil
    end

    def queue_jobs
      queue_job_relation&.order(:id)&.to_a || []
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => error
      raise unless optional_backend_unavailable?(error)

      []
    end

    def purge_queue_jobs
      jobs = queue_job_relation
      return [] unless jobs

      job_ids = jobs.pluck(:id)
      jobs.where(id: job_ids).destroy_all if job_ids.any?
      job_ids
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => error
      raise unless optional_backend_unavailable?(error)

      []
    end

    def queue_failures
      return [] unless defined?(SolidQueue::FailedExecution) && SolidQueue::FailedExecution.table_exists?

      jobs = queue_job_relation
      return [] unless jobs

      SolidQueue::FailedExecution.where(job_id: jobs.select(:id)).order(:id).to_a
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => error
      raise unless optional_backend_unavailable?(error)

      []
    end

    def cable_message_relation
      return unless defined?(SolidCable::Message) && SolidCable::Message.table_exists?

      channels = notification_channels
      channels.any? ? SolidCable::Message.where(channel: channels) : SolidCable::Message.none
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      nil
    end

    def cable_messages
      cable_message_relation&.order(:id)&.to_a || []
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => error
      raise unless optional_backend_unavailable?(error)

      []
    end

    def purge_cable_messages
      cable_message_relation&.delete_all
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => error
      raise unless optional_backend_unavailable?(error)
    end

    def notification_channels
      return [] unless tenant

      ActsAsTenant.with_tenant(tenant) do
        User.with_deleted.find_each.filter_map do |user|
          Turbo::StreamsChannel.signed_stream_name([ user, :notifications ])
        rescue StandardError
          nil
        end
      end
    end

    def json_safe(attributes)
      attributes.transform_values do |value|
        if value.is_a?(String) && value.encoding == Encoding::BINARY
          { "base64" => Base64.strict_encode64(value) }
        else
          value
        end
      end
    end

    def optional_backend_unavailable?(error)
      error.is_a?(ActiveRecord::NoDatabaseError) || error.message.match?(/no such table|does not exist/i)
    end
  end
end
