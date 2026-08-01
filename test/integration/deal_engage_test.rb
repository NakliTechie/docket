require "test_helper"

# D-0: an OPEN deal can start an engagement project (pre-quote studies), via the
# console and the API — mirroring onboard, but not gated on won.
class DealEngageTest < ActionDispatch::IntegrationTest
  def template
    @template ||= begin
      t = ProjectTemplate.create!(name: "Study pack", key_prefix: "ENG")
      t.project_template_items.create!(title: "Feasibility study", kind: :task, position: 1)
      t
    end
  end

  def open_deal
    Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales), contact: contacts(:asha),
                 organisation: organisations(:dpg), owner: users(:admin))
  end

  test "console: an admin engages an open deal into an engagement project" do
    sign_in_as users(:admin)
    deal = open_deal
    assert_difference [ "Project.count", "WorkItem.count", "WorkLink.count" ], 1 do
      post engage_deal_path(deal), params: { project_template_id: template.id }
    end
    project = deal.reload.onboarding_project
    assert_redirected_to project_path(project)
    assert project.kind_engagement?
    assert project.work_items.first.work_links.relation_study_for.exists?(linkable: deal)
  end

  test "API: crm:write token engages an open deal and returns the project" do
    deal = open_deal
    post "/api/v1/deals/#{deal.id}/engage", params: { project_template_id: template.id },
         headers: auth_header(api_token_for(users(:admin))), as: :json
    assert_response :created
    assert_equal "engagement", Project.find(response.parsed_body["data"]["id"]).kind
  end

  test "API: a token without crm scope is refused" do
    deal = open_deal
    post "/api/v1/deals/#{deal.id}/engage", params: { project_template_id: template.id },
         headers: auth_header(service_token_for(%w[cases:read])), as: :json
    assert_response :forbidden
  end
end
