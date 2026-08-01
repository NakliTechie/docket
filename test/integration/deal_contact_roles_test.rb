require "test_helper"

class DealContactRolesTest < ActionDispatch::IntegrationTest
  def deal
    @deal ||= Deal.create!(name: "D", pipeline: pipelines(:sales), contact: contacts(:asha), owner: users(:sales))
  end

  test "console: add then remove a contact role on a deal" do
    sign_in_as users(:sales)
    assert_difference "DealContactRole.count", 1 do
      post deal_contact_roles_path(deal), params: { deal_contact_role: { contact_id: contacts(:asha).id, role: "champion" } }
    end
    link = DealContactRole.order(:id).last
    assert_redirected_to deal_path(deal)

    delete deal_contact_role_path(link)
    assert_not DealContactRole.exists?(link.id)
  end

  test "API: crm:write assigns a contact role" do
    post "/api/v1/deals/#{deal.id}/contact_roles",
         params: { deal_contact_role: { contact_id: contacts(:asha).id, role: "decision_maker" } },
         headers: auth_header(service_token_for(%w[crm:read crm:write])), as: :json
    assert_response :created
    assert_equal "decision_maker", response.parsed_body["data"]["role"]
  end
end
