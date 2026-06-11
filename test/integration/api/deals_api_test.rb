require "test_helper"

module Api
  class DealsApiTest < ActionDispatch::IntegrationTest
    test "crm:write creates and moves a deal; crm:read lists" do
      write = service_token_for(%w[crm:read crm:write])

      post "/api/v1/deals", params: { deal: { name: "API Deal", pipeline_id: pipelines(:sales).id, value: "5000" } },
           headers: auth_header(write), as: :json
      assert_response :created
      deal_id = response.parsed_body["data"]["id"]
      assert_equal pipeline_stages(:sales_new).id, response.parsed_body["data"]["pipeline_stage_id"]
      assert_equal 500_000, response.parsed_body["data"]["value_cents"]

      post "/api/v1/deals/#{deal_id}/move", params: { pipeline_stage_id: pipeline_stages(:sales_won).id },
           headers: auth_header(write), as: :json
      assert_response :success
      assert_equal "won", response.parsed_body["data"]["status"]

      get "/api/v1/deals", params: { status: "won" }, headers: auth_header(service_token_for(%w[crm:read]))
      assert_response :success
      assert response.parsed_body["data"].any? { |d| d["id"] == deal_id }
    end

    test "pipelines are listable with crm:read and serialized with stages" do
      get "/api/v1/pipelines", headers: auth_header(service_token_for(%w[crm:read]))
      assert_response :success
      sales = response.parsed_body["data"].find { |p| p["slug"] == "sales" }
      assert sales["stages"].any? { |s| s["name"] == "Won" && s["is_won"] }
    end

    test "a token without crm scope is refused" do
      post "/api/v1/deals", params: { deal: { name: "x", pipeline_id: pipelines(:sales).id } },
           headers: auth_header(service_token_for(%w[cases:read])), as: :json
      assert_response :forbidden
    end
  end
end
