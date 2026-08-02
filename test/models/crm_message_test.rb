require "test_helper"

class CrmMessageTest < ActiveSupport::TestCase
  test "records a tenant-scoped CRM message and builds a linked conversation" do
    lead = Lead.create!(name: "Asha lead", email: contacts(:asha).email)
    deal = Deal.create!(name: "Asha deal", pipeline: pipelines(:sales), contact: contacts(:asha), lead: lead)
    message = CrmMessage.create!(
      subject: deal, author: users(:sales), channel: :email, direction: :outbound,
      delivery_status: :recorded, sender_email: users(:sales).email_address,
      recipient_email: contacts(:asha).email, subject_line: "Proposal", body: "Attached proposal"
    )

    entries = CrmConversation.call(contacts(:asha), visible_types: %w[Contact Lead Deal])

    assert_includes entries.map(&:record), message
    assert_equal "Deal: Asha deal", entries.find { |entry| entry.record == message }.context
  end

  test "rejects cross-tenant subjects and authors" do
    other = ActsAsTenant.with_tenant(tenants(:acme)) do
      Contact.create!(name: "Other", email: "other@example.test")
    end
    message = CrmMessage.new(subject: other, author: users(:sales), body: "No",
                             delivery_status: :recorded)

    assert_not message.valid?
    assert message.errors[:subject].any?
  end

  test "reserves an inbound email identity after soft deletion" do
    original = CrmMessage.create!(subject: contacts(:asha), body: "First",
                                  direction: :inbound, delivery_status: :recorded,
                                  email_message_id: "crm-replay@example.test")
    original.destroy
    replay = CrmMessage.new(subject: contacts(:asha), body: "Replay",
                            direction: :inbound, delivery_status: :recorded,
                            email_message_id: "crm-replay@example.test")

    assert_not replay.valid?
    assert replay.errors[:email_message_id].any?
  end

  test "validates CRM identity fields and deal follow-up pairing" do
    contact = contacts(:asha)
    contact.assign_attributes(job_title: " Buyer ", whatsapp_handle: "+91 98765 43210",
                              telegram_handle: "@asha_buyer")
    assert contact.valid?
    contact.save!
    assert_equal "Buyer", contact.job_title
    assert_equal "+919876543210", contact.whatsapp_handle
    assert_equal "asha_buyer", contact.telegram_handle

    deal = Deal.new(name: "Follow-up", pipeline: pipelines(:sales), next_step_at: 1.day.from_now)
    assert_not deal.valid?
    deal.next_step = "Send revised proposal"
    assert deal.valid?
  end
end
