require "test_helper"

class LeadsTest < ActionDispatch::IntegrationTest
  test "an agent can capture, view, convert and unqualify a lead" do
    sign_in_as users(:agent_a)

    assert_difference "Lead.count", 1 do
      post leads_path, params: { lead: { name: "Walkin Prospect", email: "walkin@example.com",
                                         company_name: "Walkin Co", source: "manual", value_estimate: "2500" } }
    end
    lead = Lead.order(:id).last
    assert_redirected_to lead_path(lead)
    assert_equal 250_000, lead.value_estimate_cents

    get lead_path(lead)
    assert_response :success

    assert_difference "Contact.count", 1 do
      post convert_lead_path(lead)
    end
    assert lead.reload.status_converted?
    assert_redirected_to contact_path(lead.contact)
  end

  test "mark unqualified from the console" do
    sign_in_as users(:agent_a)
    lead = Lead.create!(name: "Cold", email: "cold@example.com")
    post mark_unqualified_lead_path(lead)
    assert lead.reload.status_unqualified?
  end

  test "leads index is searchable and filterable by status" do
    sign_in_as users(:supervisor)
    Lead.create!(name: "Findme Corp", email: "findme@example.com", status: :qualified)
    get leads_path, params: { q: "Findme", status: "qualified" }
    assert_response :success
    assert_match "Findme Corp", response.body
  end

  test "readonly users cannot create leads" do
    sign_in_as users(:readonly)
    assert_no_difference "Lead.count" do
      post leads_path, params: { lead: { name: "Nope", email: "n@example.com" } }
    end
    assert_response :forbidden
  end

  test "anonymous users are redirected" do
    get leads_path
    assert_redirected_to new_session_path
  end
end
