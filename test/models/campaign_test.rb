require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  test "normalizes identity fields and matches active UTM windows" do
    campaign = Campaign.create!(
      name: "Summer launch", code: "Summer Launch", status: :active,
      channel: :paid_search, starts_on: 1.day.ago, ends_on: 1.day.from_now,
      utm_source: " Google ", utm_medium: " CPC ", utm_campaign: " Summer-26 ",
      budget: "1250.50", currency: "inr"
    )

    assert_equal "summer-launch", campaign.code
    assert_equal "summer-26", campaign.utm_campaign
    assert_equal 125_050, campaign.budget_cents
    assert_equal campaign, Campaign.matching_utm("SUMMER-26")
  end

  test "draft and expired campaigns do not match incoming UTM" do
    draft = Campaign.create!(name: "Draft", code: "draft", status: :draft,
                             utm_campaign: "draft-campaign")
    expired = Campaign.create!(name: "Expired", code: "expired", status: :active,
                               ends_on: 1.day.ago, utm_campaign: "expired-campaign")

    assert_nil Campaign.matching_utm(draft.utm_campaign)
    assert_nil Campaign.matching_utm(expired.utm_campaign)
  end

  test "requires a valid date window and unique UTM campaign" do
    Campaign.create!(name: "Original", code: "original", utm_campaign: "shared")
    duplicate = Campaign.new(name: "Duplicate", code: "duplicate", utm_campaign: "SHARED")
    invalid_window = Campaign.new(name: "Window", code: "window", utm_campaign: "window",
                                  starts_on: Date.current, ends_on: 1.day.ago)

    assert_not duplicate.valid?
    assert_not invalid_window.valid?
    assert invalid_window.errors[:ends_on].any?
  end

  test "first-touch links reject campaigns from another tenant" do
    foreign = ActsAsTenant.with_tenant(tenants(:acme)) do
      Campaign.create!(name: "Foreign", code: "foreign", utm_campaign: "foreign")
    end
    lead = Lead.new(name: "Local", email: "local.campaign@example.com",
                    first_touch_campaign_id: foreign.id)

    assert_not lead.valid?
    assert lead.errors.of_kind?(:first_touch_campaign, :cross_tenant)
  end
end
