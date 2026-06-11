require "test_helper"

module Api
  class SequencesApiTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    test "admin token creates a sequence; crm:read lists it" do
      post "/api/v1/sequences", params: { sequence: {
        name: "API Seq", active: true,
        sequence_steps_attributes: [ { position: 0, delay_days: 0, body: "Hi" } ]
      } }, headers: auth_header(@admin_token), as: :json
      assert_response :created
      assert_equal 1, response.parsed_body["data"]["steps"].size

      get "/api/v1/sequences", headers: auth_header(service_token_for(%w[crm:read]))
      assert_response :success
      assert response.parsed_body["data"].any? { |s| s["name"] == "API Seq" }
    end

    test "crm:write enrolls a lead and cancels it" do
      seq = Sequence.new(name: "Enroller")
      seq.sequence_steps.build(position: 0, delay_days: 0, body: "x")
      seq.save!
      lead = Lead.create!(name: "API Target", email: "api.target@example.com")
      write = service_token_for(%w[crm:read crm:write])

      post "/api/v1/sequence_enrollments",
           params: { sequence_id: seq.id, enrollable_type: "Lead", enrollable_id: lead.id },
           headers: auth_header(write), as: :json
      assert_response :created
      enr_id = response.parsed_body["data"]["id"]

      post "/api/v1/sequence_enrollments/#{enr_id}/cancel", headers: auth_header(write), as: :json
      assert_response :success
      assert_equal "cancelled", response.parsed_body["data"]["status"]
    end

    test "a token without crm scope is refused" do
      get "/api/v1/sequences", headers: auth_header(service_token_for(%w[cases:read]))
      assert_response :forbidden
    end
  end
end
