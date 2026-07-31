require "test_helper"

module Api
  class WorkItemRelationsApiTest < ActionDispatch::IntegrationTest
    test "service accounts create and remove relations within visible work" do
      token = service_token_for(%w[work:read work:write])
      source, target = work_items(:pep_one), work_items(:pep_two)
      post "/api/v1/work_items/#{source.id}/relations", params: { work_item_relation: {
        relation_type: "duplicates", target_id: target.id
      } }, headers: auth_header(token), as: :json
      assert_response :created
      id = response.parsed_body.dig("data", "id")

      get "/api/v1/work_items/#{source.id}", headers: auth_header(token)
      assert_response :success
      assert_equal "duplicates", response.parsed_body.dig("data", "relations", 0, "relation_type")

      delete "/api/v1/work_item_relations/#{id}", headers: auth_header(token)
      assert_response :no_content
    end
  end
end
