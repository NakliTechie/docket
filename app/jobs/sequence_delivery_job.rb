# Claims and performs one durable sequence-delivery receipt. Claiming happens
# before the external call, so a worker crash is recorded as an uncertain
# `attempting` row and is intentionally not retried: duplicate outreach is the
# failure mode this outbox is designed to prevent.
class SequenceDeliveryJob < ApplicationJob
  queue_as :default

  def perform(delivery_id)
    delivery = SequenceDelivery.find_by(id: delivery_id)
    return unless delivery&.claim!

    case delivery.channel
    when "email" then deliver_email(delivery)
    when "sms" then deliver_sms(delivery)
    end
  rescue StandardError => e
    delivery&.mark_failed!(e.message) if delivery&.status_attempting?
    Rails.logger.warn("[sequence] delivery #{delivery_id} failed: #{e.message}")
  end

  private

  def deliver_email(delivery)
    unless OutboundMail.available?
      delivery.mark_skipped!("outbound email is not configured")
      return
    end

    CrmMailer.sequence_delivery(delivery).deliver_now
    delivery.mark_delivered!
  end

  def deliver_sms(delivery)
    connector = delivery.connector
    unless connector&.operational?
      delivery.mark_skipped!("connector is not active and configured")
      return
    end

    Comms::SmsGateway.new(connector).deliver(
      mobile: delivery.recipient,
      variables: delivery.payload.fetch("variables", {})
    )
    delivery.mark_delivered!
  end
end
