# Fan-out publisher: one delivery row + one async job per subscribed
# endpoint. Payloads are self-contained JSON; receivers verify the
# X-Docket-Signature HMAC.
module Webhooks
  module_function

  # An event whose module is off must not leave the building: the recurring
  # sweeps are gated, but these fire from model callbacks, so a disabled
  # module's data was still being posted outward by any code path that
  # created a record.
  EVENT_FEATURES = {
    "work_item" => "work",
    "case" => "service_desk"
  }.freeze

  def publish(event, payload)
    owner = EVENT_FEATURES[event.to_s.split(".").first]
    return if owner && !Features.enabled?(owner)

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

  # Work-module payload. Deliberately mirrors case_payload's shape (id + human
  # reference + state) so a subscriber handling both does not need two parsers.
  def work_item_payload(item)
    {
      id: item.id,
      reference: item.reference,
      project_key: item.project&.key,
      title: item.title,
      kind: item.kind,
      priority: item.priority,
      state: item.workflow_state&.name,
      state_category: item.workflow_state&.category,
      assignee_id: item.assignee_id,
      sprint_id: item.sprint_id,
      closed_at: item.closed_at
    }
  end
end
