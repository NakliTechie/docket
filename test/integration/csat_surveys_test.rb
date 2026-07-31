require "test_helper"

class CsatSurveysTest < ActionDispatch::IntegrationTest
  setup do
    @survey = CsatSurvey.create!(case: cases(:pension_case), contact: contacts(:asha),
                                 invited_at: Time.current)
    @token = @survey.signed_id(purpose: :csat, expires_in: 90.days)
  end

  test "a customer submits one public response" do
    get csat_survey_path(@token)
    assert_response :success
    assert_match cases(:pension_case).tracking_id, response.body

    post csat_survey_path(@token), params: { csat_survey: { score: 4, comment: "Helpful" } }
    assert_response :created
    assert_equal 4, @survey.reload.score
    assert_equal "Helpful", @survey.comment

    post csat_survey_path(@token), params: { csat_survey: { score: 1, comment: "Overwrite" } }
    assert_response :created
    assert_equal 4, @survey.reload.score
  end

  test "an invalid or expired token is not accepted" do
    get csat_survey_path("invalid")
    assert_response :not_found
  end
end
