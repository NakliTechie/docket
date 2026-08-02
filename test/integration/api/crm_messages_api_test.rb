require "test_helper"

module Api
  class CrmMessagesApiTest < ActionDispatch::IntegrationTest
    test "CRM scopes list a lead conversation and compose email" do
      lead = Lead.create!(name: "API lead", email: "api.lead@example.test")
      token = service_token_for(%w[crm:read crm:write])

      assert_difference "CrmMessage.count", 1 do
        post "/api/v1/crm_messages", params: {
          subject_type: "Lead", subject_id: lead.id,
          crm_message: { subject_line: "API hello", body: "API body" }
        }, headers: auth_header(token), as: :json
      end
      assert_response :created
      assert_equal "pending", response.parsed_body.dig("data", "delivery_status")

      get "/api/v1/crm_messages", params: { subject_type: "Lead", subject_id: lead.id },
          headers: auth_header(token), as: :json
      assert_response :success
      assert_equal "API body", response.parsed_body.dig("data", 0, "body")
    end

    test "CRM read scope cannot compose and cannot address a Contact without contact scope" do
      token = service_token_for(%w[crm:read])
      lead = Lead.create!(name: "Read lead", email: "read.lead@example.test")

      post "/api/v1/crm_messages", params: {
        subject_type: "Lead", subject_id: lead.id,
        crm_message: { subject_line: "No", body: "No" }
      }, headers: auth_header(token), as: :json
      assert_response :forbidden

      get "/api/v1/crm_messages", params: { subject_type: "Contact", subject_id: contacts(:asha).id },
          headers: auth_header(token), as: :json
      assert_response :forbidden
    end

    test "linked records remain behind their own scopes" do
      contact = Contact.create!(name: "Scoped contact", email: "scoped.contact@example.test")
      lead = Lead.create!(name: "Scoped lead", email: contact.email, contact: contact)
      deal = Deal.create!(name: "Scoped deal", pipeline: pipelines(:sales), contact: contact, lead: lead)
      CrmMessage.create!(subject: contact, body: "Contact-scoped message", direction: :inbound,
                         delivery_status: :recorded, sender_email: contact.email)
      CrmMessage.create!(subject: deal, body: "Deal-scoped message", direction: :inbound,
                         delivery_status: :recorded, sender_email: contact.email)

      get "/api/v1/crm_messages", params: { subject_type: "Contact", subject_id: contact.id },
          headers: auth_header(service_token_for(%w[contacts:read])), as: :json
      assert_response :success
      assert_equal [ "Contact-scoped message" ], response.parsed_body["data"].pluck("body")

      get "/api/v1/crm_messages", params: { subject_type: "Deal", subject_id: deal.id },
          headers: auth_header(service_token_for(%w[crm:read])), as: :json
      assert_response :success
      assert_equal [ "Deal-scoped message" ], response.parsed_body["data"].pluck("body")
    end
  end
end
