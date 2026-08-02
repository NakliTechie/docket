require "test_helper"

module Api
  class CampaignsApiTest < ActionDispatch::IntegrationTest
    test "CRM API creates and lists campaigns" do
      token = api_token_for(users(:admin))
      post "/api/v1/campaigns", params: { campaign: {
        name: "API Campaign", code: "api-campaign", status: "active",
        channel: "email", utm_campaign: "api-campaign-26", budget_cents: 75_000,
        currency: "INR"
      } }, headers: auth_header(token), as: :json

      assert_response :created
      assert_equal "api-campaign-26", response.parsed_body.dig("data", "utm_campaign")

      get "/api/v1/campaigns", headers: auth_header(service_token_for(%w[crm:read]))
      assert_response :success
      assert response.parsed_body["data"].any? { |row| row["code"] == "api-campaign" }
    end

    test "CRM read scope cannot create campaigns" do
      post "/api/v1/campaigns", params: { campaign: {
        name: "Denied", code: "denied", utm_campaign: "denied"
      } }, headers: auth_header(service_token_for(%w[crm:read])), as: :json

      assert_response :forbidden
    end
  end
end
