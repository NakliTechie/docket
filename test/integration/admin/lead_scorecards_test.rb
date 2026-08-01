require "test_helper"

module Admin
  class LeadScorecardsTest < ActionDispatch::IntegrationTest
    test "a pipeline manager views and edits the scorecard" do
      sign_in_as users(:client_admin)

      get admin_lead_scorecard_path
      assert_response :success

      patch admin_lead_scorecard_path, params: { lead_scorecard: {
        weight_email: 2, warm_threshold: 4, hot_threshold: 8, warm_sources: "referral"
      } }
      assert_redirected_to admin_lead_scorecard_path

      card = LeadScorecard.current
      assert_equal 2, card.weight_email
      assert_equal %w[referral], card.warm_source_list
    end

    test "an invalid scorecard (hot below warm) re-renders the form" do
      sign_in_as users(:client_admin)
      patch admin_lead_scorecard_path, params: { lead_scorecard: { warm_threshold: 9, hot_threshold: 2 } }
      assert_response :unprocessable_entity
    end

    test "a user without pipeline:manage is forbidden" do
      sign_in_as users(:sales) # has lead:write, not pipeline:manage
      get admin_lead_scorecard_path
      assert_response :forbidden
    end
  end
end
