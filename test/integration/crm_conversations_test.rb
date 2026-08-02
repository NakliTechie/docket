require "test_helper"

class CrmConversationsTest < ActionDispatch::IntegrationTest
  test "sales can view a linked thread and queue an email" do
    sign_in_as users(:sales)
    lead = Lead.create!(name: "Conversation lead", email: "conversation@example.test")
    CrmMessage.create!(subject: lead, body: "Existing reply", direction: :inbound,
                       sender_email: lead.email, delivery_status: :recorded)

    get lead_path(lead)
    assert_response :success
    assert_select "#crm-conversation", text: /Existing reply/
    assert_includes response.body, CrmMailboxAddress.address_for(lead)

    assert_difference "CrmMessage.count", 1 do
      post crm_messages_path, params: { crm_message: {
        subject_type: "Lead", subject_id: lead.id, subject_line: "Follow up", body: "Can we talk?"
      } }
    end
    assert_redirected_to lead_path(lead)
    assert CrmMessage.order(:id).last.delivery_status_pending?
  end

  test "readonly cannot compose a CRM email" do
    sign_in_as users(:readonly)
    lead = Lead.create!(name: "Read only", email: "readonly.lead@example.test")

    assert_no_difference "CrmMessage.count" do
      post crm_messages_path, params: { crm_message: {
        subject_type: "Lead", subject_id: lead.id, subject_line: "No", body: "No"
      } }
    end
    assert_response :forbidden
  end

  test "a contact reader cannot see messages attached to linked sales records" do
    sign_in_as users(:customer_service)
    contact = Contact.create!(name: "Shared contact", email: "shared.contact@example.test")
    deal = Deal.create!(name: "Restricted deal", pipeline: pipelines(:sales), contact: contact)
    CrmMessage.create!(subject: contact, body: "Shared contact message", direction: :inbound,
                       delivery_status: :recorded, sender_email: contact.email)
    CrmMessage.create!(subject: deal, body: "Sales-only message", direction: :inbound,
                       delivery_status: :recorded, sender_email: contact.email)

    get contact_path(contact)

    assert_response :success
    assert_includes response.body, "Shared contact message"
    refute_includes response.body, "Sales-only message"
  end
end
