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
    contact = Contact.create!(name: "Private Person", email: "private-73f9@example.test",
                              phone: "+9199999973", external_id: "CIF-PRIVATE-73F9",
                              notes: marker)
    kase = Case.create!(subject: "Request #{marker}", description: "Description #{marker}",
                        contact: contact)
    message = kase.messages.create!(body: "Message #{marker}", kind: :internal_note,
                                    author: users(:agent_a), direction: :outbound)
    message.files.attach(io: StringIO.new(marker), filename: "private.txt",
                         content_type: "text/plain")
    blob_id = message.files.first.blob_id
    endpoint = WebhookEndpoint.create!(name: "Privacy webhook", url: "https://example.com/hook",
                                       events: [ "case.created" ], active: false)
    WebhookDelivery.create!(webhook_endpoint: endpoint, event: "case.created",
                            payload: { subject: marker }, status: :delivered)

    result = Privacy::EraseContact.call(contact: contact)

    contact.reload
    assert contact.deleted?
    assert contact.erased_at.present?
    assert_nil contact.email
    assert_nil contact.phone
    assert_match(/\Aerased-/, contact.external_id)
    assert_nil kase.reload.description
    assert_equal "[Erased for privacy]", message.reload.body
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
