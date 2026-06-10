# Fan-out publisher: one delivery row + one async job per subscribed
# endpoint. Payloads are self-contained JSON; receivers verify the
# X-Docket-Signature HMAC.
module Webhooks
  module_function

  def publish(event, payload)
    WebhookEndpoint.subscribed_to(event).each do |endpoint|
      delivery = endpoint.webhook_deliveries.create!(
        event: event,
        payload: { event: event, occurred_at: Time.current.utc.iso8601(3), data: payload }
      )
      WebhookDeliveryJob.perform_later(delivery)
    end
  end

  def case_payload(kase)
    {
      id: kase.id,
      tracking_id: kase.tracking_id,
      subject: kase.subject,
      status: kase.status,
      priority: kase.priority,
      channel: kase.channel,
      queue: kase.queue&.slug,
      category: kase.category&.name,
      assignee_id: kase.assignee_id,
      contact: {
        id: kase.contact_id,
        external_id: kase.contact&.external_id
      },
      created_at: kase.created_at&.utc&.iso8601(3),
      updated_at: kase.updated_at&.utc&.iso8601(3)
    }
  end
end
