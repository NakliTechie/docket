require "test_helper"

class CsatReportsTest < ActionDispatch::IntegrationTest
  setup do
    CsatSurvey.create!(case: cases(:pension_case), contact: contacts(:asha),
                       invited_at: Time.current, sent_at: Time.current,
                       score: 4, comment: "Fast help", responded_at: Time.current)
  end

  test "an operational reporter sees totals and exports comments" do
    sign_in_as users(:admin)
    get csat_report_path
    assert_response :success
    assert_match "Customer satisfaction", response.body
    assert_match "Fast help", response.body

    get csat_report_path(format: :csv)
    assert_response :success
    assert_match "tracking_id,score,comment,responded_at", response.body
  end

  test "the API exposes aggregate data but not customer comments" do
    token = api_token_for(users(:admin))
    get "/api/v1/reports/csat", headers: auth_header(token)
    assert_response :success
    assert_equal 4.0, response.parsed_body.dig("data", "average_score")
    refute response.parsed_body.dig("data").key?("comments")
  end
end
