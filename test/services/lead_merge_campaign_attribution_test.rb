require "test_helper"

class LeadMergeCampaignAttributionTest < ActiveSupport::TestCase
  test "merge keeps the earliest available first touch" do
    campaign = Campaign.create!(name: "Source", code: "source", utm_campaign: "source")
    target = Lead.create!(name: "Target", email: "target.merge.campaign@example.com")
    source = Lead.create!(
      name: "Source", email: "source.merge.campaign@example.com",
      first_touch_campaign: campaign, first_touch_at: 2.days.ago,
      first_touch_utm_source: "partner", first_touch_utm_campaign: "source"
    )

    LeadMerge.call(source: source, target: target, actor: users(:admin))

    assert_equal campaign, target.reload.first_touch_campaign
    assert_equal "partner", target.first_touch_utm_source
    assert_equal "source", target.first_touch_utm_campaign
  end
end
