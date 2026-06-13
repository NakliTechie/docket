require "test_helper"

# Forward pass — Batch G API polish (M4, L3, L2).
module Api
  module V1
    class ForwardPassGTest < ActionDispatch::IntegrationTest
      # M4 — a config:write-only service account can write settings without a
      # 403 from the (removed) config:read re-gate.
      test "settings update succeeds for a config:write-only token" do
        token = service_token_for(%w[config:write])
        patch "/api/v1/settings", params: { cors_allowed_origins: "https://app.test" }, headers: auth_header(token)
        assert_response :success
        assert_equal "https://app.test", response.parsed_body.dig("data", "cors_allowed_origins")
      end

      # L3 — a citizen (on_behalf_of) message can't be filed as a staff-only
      # internal note; it's forced to a public reply.
      test "an on-behalf-of message can't be an internal note" do
        kase = Case.create!(subject: "Citizen reply", channel: :web_portal, contact: contacts(:asha))
        token = service_token_for(%w[cases:write contacts:write])
        post "/api/v1/cases/#{kase.id}/messages",
             params: { on_behalf_of: "cust-1", contact: { name: "Cust" },
                       message: { body: "secret note", kind: "internal_note" } },
             headers: auth_header(token)
        assert_response :created
        msg = kase.messages.order(:id).last
        assert msg.kind_public_reply?, "a contact-authored message is forced to public_reply"
        assert msg.direction_inbound?
        assert_instance_of Contact, msg.author
      end

      # L2 — assigning an unknown/inactive user is a clean 422, not a 404/500.
      test "assigning an invalid user returns 422" do
        kase = Case.create!(subject: "Assign", channel: :staff, contact: contacts(:asha))
        token = api_token_for(users(:admin))
        post "/api/v1/cases/#{kase.id}/assign", params: { assignee_id: 999_999 }, headers: auth_header(token)
        assert_response :unprocessable_entity
        assert_equal "invalid_assignee", response.parsed_body["error"]
      end
    end
  end
end
