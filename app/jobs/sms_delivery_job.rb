# Backgrounds an outbound marketing SMS (a sequence step) through the shared
# Comms::SmsGateway, so the SequenceRunnerJob sweep never blocks on MSG91's
# HTTP call. System-attributed: no agent principal and no approval gate — that
# governance is for the agent effector, not operator-authored sequences.
class SmsDeliveryJob < ApplicationJob
  queue_as :default

  def perform(connector_id, mobile, variables = {})
    connector = Connector.find_by(id: connector_id)
    return unless connector&.status_active? && connector.configured?

    Comms::SmsGateway.new(connector).deliver(mobile: mobile, variables: variables)
  rescue Comms::SmsGateway::Error => e
    Rails.logger.warn("[sms] sequence delivery failed: #{e.message}")
  end
end
