require "test_helper"

module Api
  class OneDocketApiTest < ActionDispatch::IntegrationTest
    setup { @token = api_token_for(users(:admin)) }

    test "project templates and won-deal onboarding have API parity" do
      post "/api/v1/project_templates", params: { project_template: {
        name: "API onboarding", key_prefix: "API",
        project_template_items_attributes: {
          "0" => { title: "Provision account", kind: "task", priority: "normal", due_offset_days: 2 }
        }
      } }, headers: auth_header(@token), as: :json
      assert_response :created
      template_id = response.parsed_body.dig("data", "id")

      deal = Deal.create!(name: "Won on API", pipeline: pipelines(:sales),
                          pipeline_stage: pipeline_stages(:sales_won), contact: contacts(:asha))
      assert_difference "Project.count", 1 do
        post "/api/v1/deals/#{deal.id}/onboard", params: { project_template_id: template_id },
             headers: auth_header(@token), as: :json
      end
      assert_response :created
      assert_equal deal.id, response.parsed_body.dig("data", "onboarding_deal_id")
      assert_equal template_id, response.parsed_body.dig("data", "project_template_id")
    end

    test "a guarded work transition answers 202 with the pending request" do
      item = work_items(:pep_one)
      target = workflow_states(:pep_done)
      ApprovalProcess.create!(name: "API done sign-off", trigger_type: :work_item_transition,
                              trigger_key: "PEP:Done")

      post "/api/v1/work_items/#{item.id}/transition",
           params: { workflow_state_id: target.id }, headers: auth_header(@token), as: :json

      assert_response :accepted
      refute item.reload.done?
      assert_equal "pending", response.parsed_body.dig("approval_request", "status")
      assert_equal target.id.to_s, response.parsed_body.dig("approval_request", "requested_action")
    end
  end
end
