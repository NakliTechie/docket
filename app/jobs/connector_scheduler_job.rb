# Recurring (config/recurring.yml): enqueues a sync for every active
# connector whose schedule interval has elapsed. Webhook- and manual-only
# connectors (no interval) are skipped here and driven on demand.
class ConnectorSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    each_active_tenant do
      Connector.active.find_each do |connector|
        ConnectorSyncJob.perform_later(connector.id, trigger: "scheduled") if connector.due?
      end
    end
  end
end
