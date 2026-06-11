# Runs one connector's sync off the request thread (manual "Sync now",
# the scheduler, or a webhook ping all enqueue this).
class ConnectorSyncJob < ApplicationJob
  queue_as :default

  def perform(connector_id, trigger: "scheduled")
    connector = Connector.find_by(id: connector_id)
    return unless connector

    Connectors::Sync.run(connector, trigger: trigger)
  end
end
