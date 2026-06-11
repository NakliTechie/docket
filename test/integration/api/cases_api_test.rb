require "test_helper"

module Api
  class CasesApiTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    test "lists and filters cases" do
      get "/api/v1/cases", params: { status: "in_progress" }, headers: auth_header(@admin_token)
      assert_response :success
      data = response.parsed_body["data"]
      assert data.all? { |c| c["status"] == "in_progress" }

      get "/api/v1/cases", params: { contact_external_id: contacts(:ravi).external_id },
          headers: auth_header(@admin_token)
      assert response.parsed_body["data"].any?
    end

    test "shows a case by id or tracking id with messages" do
      kase = cases(:pension_case)
      get "/api/v1/cases/#{kase.tracking_id}", params: { include: "messages" },
          headers: auth_header(@admin_token)
      assert_response :success
      body = response.parsed_body["data"]
      assert_equal kase.id, body["id"]
      assert body["messages"].is_a?(Array)
      assert_includes body.keys, "allowed_transitions"
    end

    test "creates, transitions, assigns, and deletes via user token" do
      post "/api/v1/cases", params: {
        case: { subject: "API filed", contact_id: contacts(:asha).id, priority: "high" }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :created
      id = response.parsed_body["data"]["id"]
      assert_equal "api", response.parsed_body["data"]["channel"]

      post "/api/v1/cases/#{id}/transition", params: { status: "triaged" },
           headers: auth_header(@admin_token), as: :json
      assert_response :success
      assert_equal "triaged", response.parsed_body["data"]["status"]

      post "/api/v1/cases/#{id}/transition", params: { status: "closed" },
           headers: auth_header(@admin_token), as: :json
      assert_response :unprocessable_entity

      post "/api/v1/cases/#{id}/assign", params: { assignee_id: users(:agent_a).id },
           headers: auth_header(@admin_token), as: :json
      assert_equal users(:agent_a).id, response.parsed_body["data"]["assignee_id"]

      delete "/api/v1/cases/#{id}", headers: auth_header(@admin_token)
      assert_response :no_content
      refute Case.exists?(id)
      assert Case.with_deleted.exists?(id)
    end

    test "service account files a case on behalf of a customer by external id" do
      token = service_token_for(%w[cases:read cases:write contacts:write])
      assert_difference "Contact.count" do
        post "/api/v1/cases", params: {
          on_behalf_of: "CIF900001",
          contact: { name: "New Customer", email: "newcif@example.com" },
          case: { subject: "Blocked card", message_body: "Customer reports card blocked." }
        }, headers: auth_header(token), as: :json
      end
      assert_response :created
      kase = Case.find(response.parsed_body["data"]["id"])
      assert_equal "CIF900001", kase.contact.external_id
      assert_equal 1, kase.messages.count
      assert kase.messages.first.direction_inbound?

      entry = AuditEntry.where(action: "case.create", auditable: kase).first
      assert_equal "ServiceAccount", entry.actor_type
      assert_equal "CIF900001", entry.metadata["on_behalf_of"]
    end

    test "on behalf of reuses the existing contact" do
      token = service_token_for(%w[cases:write contacts:write])
      assert_no_difference "Contact.count" do
        post "/api/v1/cases", params: {
          on_behalf_of: contacts(:ravi).external_id,
          case: { subject: "Second complaint" }
        }, headers: auth_header(token), as: :json
      end
      assert_equal contacts(:ravi).id, response.parsed_body["data"]["contact_id"]
    end

    test "on behalf of without contacts:write is denied" do
      token = service_token_for(%w[cases:write])
      post "/api/v1/cases", params: {
        on_behalf_of: "CIF900002", case: { subject: "Nope" }
      }, headers: auth_header(token), as: :json
      assert_response :forbidden
    end

    test "an unauthorized case create does not upsert the OBO contact (authz before side-effect, M23)" do
      token = service_token_for(%w[cases:read contacts:write]) # no cases:write
      assert_no_difference "Contact.count" do
        post "/api/v1/cases", params: { on_behalf_of: "CIFGHOST1", case: { subject: "x" } },
             headers: auth_header(token), as: :json
      end
      assert_response :forbidden
    end

    test "a failed case create rolls back the OBO contact (transactional, M23)" do
      token = service_token_for(%w[cases:write contacts:write])
      assert_no_difference "Contact.count" do # blank subject -> case invalid -> rollback
        post "/api/v1/cases", params: { on_behalf_of: "CIFROLLBACK1", case: { subject: "" } },
             headers: auth_header(token), as: :json
      end
      assert_response :unprocessable_entity
    end

    test "cases:read scope cannot write" do
      token = service_token_for(%w[cases:read])
      post "/api/v1/cases", params: { case: { subject: "Nope", contact_id: contacts(:asha).id } },
           headers: auth_header(token), as: :json
      assert_response :forbidden
      post "/api/v1/cases/#{cases(:pension_case).id}/transition", params: { status: "triaged" },
           headers: auth_header(token), as: :json
      assert_response :forbidden
    end

    test "readonly user tokens cannot mutate" do
      token = api_token_for(users(:readonly))
      get "/api/v1/cases", headers: auth_header(token)
      assert_response :success
      post "/api/v1/cases", params: { case: { subject: "Nope", contact_id: contacts(:asha).id } },
           headers: auth_header(token), as: :json
      assert_response :forbidden
    end

    test "status cannot be mass-assigned through the api" do
      patch "/api/v1/cases/#{cases(:pension_case).id}",
            params: { case: { subject: "Renamed", status: "closed" } },
            headers: auth_header(@admin_token), as: :json
      assert_response :success
      assert_equal "new", cases(:pension_case).reload.status
    end

    test "messages endpoint lists and creates" do
      kase = cases(:pension_case)
      get "/api/v1/cases/#{kase.id}/messages", headers: auth_header(@admin_token)
      assert_response :success

      post "/api/v1/cases/#{kase.id}/messages", params: { message: { body: "Via API", kind: "internal_note" } },
           headers: auth_header(@admin_token), as: :json
      assert_response :created
      assert_equal "internal_note", response.parsed_body["data"]["kind"]
      assert_equal "User", response.parsed_body["data"]["author_type"]
    end

    test "service account message on behalf of contact is inbound from the contact" do
      token = service_token_for(%w[cases:write contacts:write])
      kase = cases(:waiting_case)
      post "/api/v1/cases/#{kase.id}/messages", params: {
        on_behalf_of: contacts(:asha).external_id.presence || "CIFX1",
        message: { body: "Customer adds info via netbanking" }
      }, headers: auth_header(token), as: :json
      assert_response :created
      body = response.parsed_body["data"]
      assert_equal "inbound", body["direction"]
    end

    test "agent turns cannot be forged through the api" do
      post "/api/v1/cases/#{cases(:pension_case).id}/messages",
           params: { message: { body: "Fake AI", kind: "agent_turn" } },
           headers: auth_header(@admin_token), as: :json
      assert_equal "public_reply", response.parsed_body["data"]["kind"]
    end

    test "a stale case update returns 409, not a silent overwrite (optimistic lock) (L)" do
      kase = cases(:pension_case)
      stale = kase.lock_version
      kase.update!(subject: "Changed elsewhere")

      patch "/api/v1/cases/#{kase.id}", params: { case: { subject: "Conflicting", lock_version: stale } },
            headers: auth_header(@admin_token), as: :json
      assert_response :conflict
      assert_equal "Changed elsewhere", kase.reload.subject
    end

    test "an on-behalf-of contact with an invalid email is a 422, not a 500 (L)" do
      assert_no_difference "Contact.count" do
        post "/api/v1/cases", params: {
          on_behalf_of: "CIF-NEW-BADMAIL",
          contact: { name: "Bad Mail", email: "not-an-email" },
          case: { subject: "OBO bad email" }
        }, headers: auth_header(@admin_token), as: :json
      end
      assert_response :unprocessable_entity
    end
  end
end
