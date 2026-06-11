require "test_helper"

class InquiriesTest < ActionDispatch::IntegrationTest
  test "the public inquiry form is reachable without authentication" do
    get inquiry_path
    assert_response :success
    assert_select "form"
  end

  test "a valid inquiry creates a web_form lead and confirms" do
    assert_difference "Lead.count", 1 do
      post inquiry_path, params: { lead_inquiry: {
        name: "Prospect Person", email: "prospect@example.com", company_name: "Prospect Co",
        message: "We'd like a demo."
      } }
    end
    assert_response :created
    lead = Lead.order(:id).last
    assert lead.source_web_form?
    assert lead.status_new?
    assert_equal "Prospect Co", lead.company_name
    assert_equal "We'd like a demo.", lead.notes
  end

  test "an inquiry with no email or phone is rejected" do
    assert_no_difference "Lead.count" do
      post inquiry_path, params: { lead_inquiry: { name: "Unreachable" } }
    end
    assert_response :unprocessable_entity
  end

  test "an over-length name is rejected" do
    assert_no_difference "Lead.count" do
      post inquiry_path, params: { lead_inquiry: { name: "x" * 201, email: "a@example.com" } }
    end
    assert_response :unprocessable_entity
  end

  test "a filled honeypot is silently dropped (no lead, but looks successful)" do
    assert_no_difference "Lead.count" do
      post inquiry_path, params: {
        lead_inquiry: { name: "Bot", email: "bot@example.com" },
        website: "http://spam.example"
      }
    end
    assert_response :created
  end
end
