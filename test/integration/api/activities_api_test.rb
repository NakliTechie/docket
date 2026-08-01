require "test_helper"

module Api
  class ActivitiesApiTest < ActionDispatch::IntegrationTest
    test "crm:write creates and completes an activity; crm:read cannot write" do
      write = service_token_for(%w[crm:read crm:write])

      assert_difference "Activity.count", 1 do
        post "/api/v1/activities", params: { activity: {
          subject_type: "Contact", subject_id: contacts(:asha).id, kind: "call", title: "Ring back"
        } }, headers: auth_header(write), as: :json
      end
      assert_response :created
      id = response.parsed_body["data"]["id"]

      post "/api/v1/activities/#{id}/complete", headers: auth_header(write), as: :json
      assert_response :success
      assert_equal "done", response.parsed_body["data"]["status"]

      read = service_token_for(%w[crm:read])
      post "/api/v1/activities", params: { activity: {
        subject_type: "Contact", subject_id: contacts(:asha).id, title: "x"
      } }, headers: auth_header(read), as: :json
      assert_response :forbidden
    end

    test "index filters by subject with crm:read" do
      activity = Activity.create!(title: "on asha", subject: contacts(:asha), kind: :note)
      get "/api/v1/activities", params: { subject_type: "Contact", subject_id: contacts(:asha).id },
          headers: auth_header(service_token_for(%w[crm:read])), as: :json
      assert_response :success
      assert_includes response.parsed_body["data"].map { |a| a["id"] }, activity.id
    end

    test "a token without crm scope is refused" do
      get "/api/v1/activities", headers: auth_header(service_token_for(%w[cases:read])), as: :json
      assert_response :forbidden
    end
  end
end
