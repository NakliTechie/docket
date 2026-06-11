require "test_helper"

module Api
  class LeadsApiTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    test "crm:write can create and convert a lead; crm:read cannot write" do
      write = service_token_for(%w[crm:read crm:write])

      post "/api/v1/leads", params: { lead: { name: "API Lead", email: "api.lead@example.com", company_name: "API Co" } },
           headers: auth_header(write), as: :json
      assert_response :created
      lead_id = response.parsed_body["data"]["id"]
      assert_equal "api", response.parsed_body["data"]["source"]

      post "/api/v1/leads/#{lead_id}/convert", headers: auth_header(write), as: :json
      assert_response :success
      assert_equal "converted", response.parsed_body["data"]["status"]
      assert response.parsed_body["contact"]["id"].present?

      read = service_token_for(%w[crm:read])
      post "/api/v1/leads", params: { lead: { name: "Denied", email: "d@example.com" } },
           headers: auth_header(read), as: :json
      assert_response :forbidden
    end

    test "index lists and filters leads with crm:read" do
      Lead.create!(name: "Listed", email: "listed@example.com", status: :qualified)
      get "/api/v1/leads", params: { status: "qualified" }, headers: auth_header(service_token_for(%w[crm:read]))
      assert_response :success
      assert response.parsed_body["data"].any? { |l| l["name"] == "Listed" }
    end

    test "a token without crm scope is refused" do
      get "/api/v1/leads", headers: auth_header(service_token_for(%w[cases:read]))
      assert_response :forbidden
    end
  end
end
