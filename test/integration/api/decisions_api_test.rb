require "test_helper"

module Api
  # REST parity for the decisioning review surface. Human-token-only:
  # invocation:review holders act; operational roles and service accounts cannot.
  class DecisionsApiTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    test "an invocation:review token runs decisioning and lists the proposals" do
      Lead.create!(name: "Hot", email: "h@x.com", phone: "+91990000001",
                   company_name: "Acme", source: :referral, status: :new)

      post "/api/v1/decisions/run", headers: auth_header(@admin_token), as: :json
      assert_response :success
      assert response.parsed_body["data"].any? { |d| d["rule"] == "lead_score" }

      get "/api/v1/decisions", headers: auth_header(@admin_token)
      assert_response :success
      assert response.parsed_body["data"].any? { |d| d["rule"] == "lead_score" }

      get "/api/v1/decisions?status=proposed", headers: auth_header(@admin_token)
      assert_response :success
      assert response.parsed_body["data"].all? { |d| d["status"] == "proposed" }
    end

    test "show returns a single decision with its contestability fields" do
      decision = proposed_confirm_decision
      get "/api/v1/decisions/#{decision.id}", headers: auth_header(@admin_token)
      assert_response :success
      body = response.parsed_body["data"]
      assert_equal decision.id, body["id"]
      assert_equal "confirm", body["decision_class"]
      assert_equal false, body["appealable"]
    end

    test "approving a parked confirm proposal applies it" do
      decision = proposed_confirm_decision
      post "/api/v1/decisions/#{decision.id}/approve", headers: auth_header(@admin_token), as: :json
      assert_response :success
      assert_equal "applied", response.parsed_body["data"]["status"]
      assert decision.reload.status_applied?
      assert_equal users(:admin).id, decision.approved_by_id
    end

    test "approving a decision of record without a reason is 422" do
      kase = Case.create!(subject: "x", contact: contacts(:asha))
      decision = Decision.create!(rule: "of_rec", version: "1", subject: kase, signal: "s",
                                  decision_class: "of_record", status: :proposed)
      post "/api/v1/decisions/#{decision.id}/approve", headers: auth_header(@admin_token), as: :json
      assert_response :unprocessable_entity
      assert_equal "decision_error", response.parsed_body["error"]
      assert decision.reload.status_proposed?
    end

    test "rejecting a parked proposal marks it rejected" do
      decision = proposed_confirm_decision
      post "/api/v1/decisions/#{decision.id}/reject", headers: auth_header(@admin_token), as: :json
      assert_response :success
      assert_equal "rejected", response.parsed_body["data"]["status"]
      assert decision.reload.status_rejected?
    end

    test "an operational role without invocation:review is forbidden" do
      get "/api/v1/decisions", headers: auth_header(api_token_for(users(:sales)))
      assert_response :forbidden
      post "/api/v1/decisions/run", headers: auth_header(api_token_for(users(:sales))), as: :json
      assert_response :forbidden
    end

    test "a service-account bearer has no reach into the decisioning surface" do
      get "/api/v1/decisions", headers: auth_header(service_token_for(%w[cases:read audit:read]))
      assert_response :forbidden
    end

    private

    def proposed_confirm_decision
      kase = Case.create!(subject: "x", contact: contacts(:asha))
      Decision.create!(rule: "sla_at_risk", version: "1", subject: kase, signal: "sla_at_risk",
                       decision_class: "confirm", status: :proposed)
    end
  end
end
