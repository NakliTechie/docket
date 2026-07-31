require "test_helper"

class PrivacyAuditRedactorTest < ActiveSupport::TestCase
  test "removes audit payload content while preserving a verifiable proof chain" do
    contact = Contact.create!(name: "Erase Proof", email: "proof-erase@example.test")
    entry = AuditEntry.where(auditable: contact).order(:id).last
    assert_includes entry.changeset.to_json, "proof-erase@example.test"

    Privacy::AuditRedactor.call(entries: AuditEntry.where(id: entry.id), subject_token: "subject-token")

    entry.reload
    assert_nil entry.changeset
    assert_nil entry.metadata
    assert entry.redacted_at.present?
    assert entry.redaction_event_id.present?
    assert AuditEntry.verify_chain(cache: false, checkpoint: false)[:ok]

    original_event_id = entry.redaction_event_id
    AuditEntry.where(id: entry.id).update_all(redaction_event_id: nil)
    result = AuditEntry.verify_chain(cache: false, checkpoint: false)
    assert_not result[:ok]
    assert_equal "invalid redaction proof", result[:reason]
  ensure
    AuditEntry.where(id: entry.id).update_all(redaction_event_id: original_event_id) if original_event_id
  end
end
