require "test_helper"

class CampaignsTest < ActionDispatch::IntegrationTest
  test "admin manages campaign definitions" do
    sign_in_as users(:admin)

    assert_difference "Campaign.count", 1 do
      post campaigns_path, params: { campaign: {
        name: "Field event", code: "field-event", status: "active", channel: "event",
        budget: "50000", currency: "INR", utm_campaign: "field-event-26"
      } }
    end

    campaign = Campaign.order(:id).last
    assert_redirected_to campaign_path(campaign)
    get campaign_path(campaign)
    assert_response :success
    assert_match "field-event-26", response.body
  end

  test "read-only users can list campaigns but cannot create them" do
    Campaign.create!(name: "Visible", code: "visible", utm_campaign: "visible")
    sign_in_as users(:readonly)

    get campaigns_path
    assert_response :success
    get new_campaign_path
    assert_response :forbidden
  end
end
