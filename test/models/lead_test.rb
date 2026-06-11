require "test_helper"

class LeadTest < ActiveSupport::TestCase
  test "requires a name and at least one of email/phone" do
    assert_not Lead.new(name: "").valid?
    lead = Lead.new(name: "No contact")
    assert_not lead.valid?
    assert lead.errors[:base].any?
    assert Lead.new(name: "Reachable", email: "x@example.com").valid?
  end

  test "value_estimate reads/writes rupees against the cents column" do
    lead = Lead.new(value_estimate: 1500.50)
    assert_equal 150_050, lead.value_estimate_cents
    assert_in_delta 1500.50, lead.value_estimate, 0.001
  end

  test "convert creates and links a contact + organisation, stamps converted" do
    lead = Lead.create!(name: "Ravi Buyer", email: "ravi.buyer@example.com",
                        company_name: "Buyer Co", source: :manual)
    contact = nil
    assert_difference [ "Contact.count", "Organisation.count" ], 1 do
      contact = lead.convert!
    end
    assert lead.reload.status_converted?
    assert_equal contact, lead.contact
    assert_equal "Buyer Co", contact.organisation.name
    assert lead.converted_at.present?
  end

  test "convert dedupes onto an existing contact by email" do
    existing = contacts(:asha)
    lead = Lead.create!(name: "Dup", email: existing.email, source: :manual)
    assert_no_difference "Contact.count" do
      assert_equal existing, lead.convert!
    end
  end

  test "convert is idempotent" do
    lead = Lead.create!(name: "Once", email: "once@example.com", source: :manual)
    first = lead.convert!
    assert_no_difference "Contact.count" do
      assert_equal first, lead.convert!
    end
  end

  test "mark_unqualified moves the status" do
    lead = Lead.create!(name: "Nope", email: "nope@example.com")
    lead.mark_unqualified!
    assert lead.reload.status_unqualified?
  end
end
