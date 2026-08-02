require "test_helper"

class PrivacyEraseContactTest < ActiveSupport::TestCase
  test "an active legal hold blocks erasure until released" do
    contact = Contact.create!(name: "Held Person", email: "held-person@example.test")
    hold = LegalHold.create!(subject: contact, reason: "Open statutory investigation")

    assert_raises(Privacy::EraseContact::Held) do
      Privacy::EraseContact.call(contact: contact)
    end

    hold.release!
    assert Privacy::EraseContact.call(contact: contact).request.status_completed?
  end

  test "pseudonymizes the contact graph, removes files and direct content, and keeps audit valid" do
    marker = "unique-private-marker-73f9"
    %w[contacts cases leads deals].each do |resource_type|
      CustomFieldDefinition.create!(resource_type: resource_type, key: "private_email",
                                    label: "Private email", field_type: :short_text)
    end
    contact = Contact.create!(name: "Private Person", email: "private-73f9@example.test",
                              phone: "+9199999973", external_id: "CIF-PRIVATE-73F9",
                              job_title: "Private buyer", whatsapp_handle: "+9199999973",
                              telegram_handle: "private_73f9",
                              notes: marker,
                              custom_fields: { private_email: "private-73f9@example.test" })
    contact.add_label("churn_risk")
    kase = Case.create!(subject: "Request #{marker}", description: "Description #{marker}",
                        contact: contact, custom_fields: { private_email: "private-73f9@example.test" })
    message = kase.messages.create!(body: "Message #{marker}", kind: :internal_note,
                                    author: users(:agent_a), direction: :outbound)
    message.files.attach(io: StringIO.new(marker), filename: "private.txt",
                         content_type: "text/plain")
    blob_id = message.files.first.blob_id
    endpoint = WebhookEndpoint.create!(name: "Privacy webhook", url: "https://example.com/hook",
                                       events: [ "case.created" ], active: false)
    WebhookDelivery.create!(webhook_endpoint: endpoint, event: "case.created",
                            payload: { subject: marker }, status: :delivered)
    sequence = Sequence.new(name: "Privacy sequence")
    sequence.sequence_steps.build(position: 0, delay_days: 0, body: "Private outreach")
    sequence.save!
    enrollment = sequence.enroll!(contact)
    enrollment.advance!
    delivery = enrollment.sequence_deliveries.first
    assert delivery.tracking_token.present?
    campaign = Campaign.create!(name: "Private campaign", code: "private-campaign",
                                utm_campaign: "private-campaign")
    attributed_lead = Lead.create!(
      name: "Private lead", email: "private-lead-73f9@example.test", contact: contact,
      first_touch_campaign: campaign, first_touch_utm_campaign: "private-campaign",
      first_touch_landing_page: "https://example.test/?customer=#{marker}",
      custom_fields: { private_email: "private-73f9@example.test" }
    )
    deal = Deal.create!(name: "Private deal", pipeline: pipelines(:sales), contact: contact,
                        notes: "Deal #{marker}", next_step: "Call #{marker}", next_step_at: 1.day.from_now,
                        custom_fields: { private_email: "private-73f9@example.test" })
    crm_message = CrmMessage.create!(
      subject: deal, body: "CRM #{marker}", subject_line: "Private thread",
      direction: :inbound, delivery_status: :recorded,
      sender_email: contact.email, email_message_id: "private-crm@example.test"
    )
    crm_message.files.attach(io: StringIO.new(marker), filename: "crm-private.txt",
                             content_type: "text/plain")
    crm_blob_id = crm_message.files.first.blob_id
    decision = Decision.create!(rule: "contact_risk", version: "1", subject: contact,
                                subject_label: contact.name, signal: "churn_risk",
                                decision_class: "autonomous", status: :applied)

    result = Privacy::EraseContact.call(contact: contact)

    contact.reload
    assert contact.deleted?
    assert contact.erased_at.present?
    assert_nil contact.email
    assert_nil contact.phone
    assert_nil contact.job_title
    assert_nil contact.whatsapp_handle
    assert_nil contact.telegram_handle
    assert_match(/\Aerased-/, contact.external_id)
    assert_nil kase.reload.description
    assert_equal "[Erased for privacy]", message.reload.body
    assert_nil delivery.reload.tracking_token
    assert_nil attributed_lead.reload.first_touch_landing_page
    assert_nil attributed_lead.first_touch_utm_campaign
    assert_empty contact.custom_fields
    assert_empty contact.labels
    assert_empty kase.custom_fields
    assert_empty attributed_lead.custom_fields
    assert_empty deal.reload.custom_fields
    assert_nil deal.notes
    assert_nil deal.next_step
    assert_nil deal.next_step_at
    assert_equal "[Erased for privacy]", crm_message.reload.body
    assert_nil crm_message.sender_email
    assert_not ActiveStorage::Blob.exists?(crm_blob_id)
    assert_equal "Erased contact", decision.reload.subject_label
    assert_not ActiveStorage::Blob.exists?(blob_id)
    assert result.request.status_completed?
    assert Privacy::ResidueScanner.call(
      tenant: contact.tenant, identifiers: [ "private-73f9@example.test", "CIF-PRIVATE-73F9" ]
    ).clean?
    assert_equal marker, WebhookDelivery.find_by(webhook_endpoint: endpoint).payload["subject"],
                 "narrative text outside the subject graph must not be globally corrupted"
    assert AuditEntry.verify_chain(cache: false, checkpoint: false)[:ok]
    refute_includes AuditEntry.where(tenant_id: contact.tenant_id).pluck(:changeset, :metadata).to_json,
                    marker

    repeated = Privacy::EraseContact.call(contact: contact)
    assert_equal result.request.id, repeated.request.id
  end
end
