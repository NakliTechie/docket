# Recurring (config/recurring.yml): enqueues a sync for every active
# connector whose schedule interval has elapsed. Webhook- and manual-only
# connectors (no interval) are skipped here and driven on demand.
class ConnectorSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    each_tenant_with_feature("connectors") do
      Connector.active.find_each do |connector|
        next unless connector.due?
        next if connector.connector_runs.status_running.exists?

        ConnectorSyncJob.perform_later(connector.id, trigger: "scheduled")
      end
    end
    record_sweep_success!
  end
end
