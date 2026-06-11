require "test_helper"

class AuditEntryTest < ActiveSupport::TestCase
  test "mutations append chained audit entries" do
    contact = nil
    assert_difference "AuditEntry.count", 2 do
      contact = Contact.create!(name: "New Person", email: "new@example.com")
      contact.update!(phone: "+911234567890")
    end
    create_entry, update_entry = AuditEntry.order(:id).last(2)
    assert_equal "contact.create", create_entry.action
    assert_equal "contact.update", update_entry.action
    assert_equal create_entry.sha, update_entry.previous_sha
    assert_equal [ nil, "+911234567890" ], update_entry.changeset["phone"]
  end

  test "verify_chain passes on untampered log" do
    Contact.create!(name: "A", email: "a@example.com")
    Contact.create!(name: "B", email: "b@example.com")
    result = AuditEntry.verify_chain
    assert result[:ok], result.inspect
    assert_operator result[:count], :>=, 2
  end

  test "verify_chain caches the result and cache: false recomputes + refreshes (M27)" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      Contact.create!(name: "Cache A", email: "ca@example.com")
      first = AuditEntry.verify_chain
      assert first[:ok]

      # A new valid entry — the cached result is now stale (old count).
      Contact.create!(name: "Cache B", email: "cb@example.com")
      assert_equal first[:count], AuditEntry.verify_chain[:count], "second call served from cache"

      fresh = AuditEntry.verify_chain(cache: false)
      assert_operator fresh[:count], :>, first[:count], "uncached recomputes the current count"
      assert_equal fresh[:count], AuditEntry.verify_chain[:count], "uncached refreshed the cache"
    ensure
      Rails.cache = original
    end
  end

  test "verify_chain reports first tampered entry" do
    Contact.create!(name: "A", email: "a@example.com")
    target = Contact.create!(name: "B", email: "b@example.com")
    Contact.create!(name: "C", email: "c@example.com")
    entry = AuditEntry.where(auditable: target).first
    AuditEntry.connection.execute(
      "UPDATE audit_entries SET action = 'contact.forged' WHERE id = #{entry.id}"
    )
    result = AuditEntry.verify_chain
    refute result[:ok]
    assert_equal entry.id, result[:entry_id]
    assert_equal "entry hash mismatch", result[:reason]
  end

  test "verify_chain reports broken linkage" do
    Contact.create!(name: "A", email: "a@example.com")
    Contact.create!(name: "B", email: "b@example.com")
    last = AuditEntry.order(:id).last
    AuditEntry.connection.execute(
      "UPDATE audit_entries SET previous_sha = '#{"f" * 64}' WHERE id = #{last.id}"
    )
    result = AuditEntry.verify_chain
    refute result[:ok]
    assert_equal last.id, result[:entry_id]
    assert_equal "previous_sha mismatch", result[:reason]
  end

  test "entries are append-only at the model layer" do
    entry = AuditEntry.append!(action: "test.event", auditable: contacts(:asha))
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(action: "test.other") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy }
    assert AuditEntry.exists?(entry.id)
  end

  test "secret setting values are redacted in the changeset" do
    Setting.set("llm_api_key", "sk-very-secret")
    entry = AuditEntry.where(auditable_type: "Setting").order(:id).last
    assert_equal [ "[REDACTED]", "[REDACTED]" ], entry.changeset["value"]
    refute_includes entry.changeset.to_json, "sk-very-secret"
  end

  test "password digests never enter the audit log" do
    user = User.create!(name: "Pwd Test", email_address: "pwd@example.com",
                        password: "longenoughpassword")
    entry = AuditEntry.where(auditable: user, action: "user.create").first
    assert_equal [ "[REDACTED]", "[REDACTED]" ], entry.changeset["password_digest"]
  end

  test "actor is recorded from Current" do
    Current.set(actor: users(:admin)) do
      contact = Contact.create!(name: "With Actor", email: "actor@example.com")
      entry = AuditEntry.where(auditable: contact).first
      assert_equal users(:admin), entry.actor
    end
  end

  test "canonicalization is key-order independent" do
    entry = AuditEntry.append!(action: "test.event", auditable: contacts(:asha),
                               changeset: { "b" => 1, "a" => 2 })
    reordered = AuditEntry.canonicalize({ "a" => 2, "b" => 1 })
    assert_equal AuditEntry.canonicalize(entry.changeset), reordered
  end
end
