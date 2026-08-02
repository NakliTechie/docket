require "test_helper"

class CampaignAttributionTest < ActionDispatch::IntegrationTest
  setup do
    @campaign = Campaign.create!(
      name: "Monsoon launch", code: "monsoon-launch", status: :active,
      utm_source: "google", utm_medium: "cpc", utm_campaign: "monsoon-26"
    )
  end

  test "public inquiry captures structured UTM first touch and carries it into conversion" do
    get inquiry_path, params: {
      utm_source: "Google", utm_medium: "CPC", utm_campaign: "Monsoon-26",
      utm_term: "sovereign crm", utm_content: "hero"
    }, headers: { "HTTP_REFERER" => "https://search.example.test/results" }
    assert_response :success
    assert_select "input[name='lead_inquiry[utm_campaign]'][value='Monsoon-26']"

    assert_difference "Lead.count", 1 do
      post inquiry_path, params: { lead_inquiry: {
        name: "Asha Buyer", email: "asha.campaign@example.com",
        utm_source: "Google", utm_medium: "CPC", utm_campaign: "Monsoon-26",
        utm_term: "sovereign crm", utm_content: "hero",
        landing_page: "https://example.test/inquiry?utm_campaign=Monsoon-26",
        referrer: "https://search.example.test/results"
      } }
    end

    lead = Lead.order(:id).last
    assert_equal @campaign, lead.first_touch_campaign
    assert_equal "Google", lead.first_touch_utm_source
    assert_equal "Monsoon-26", lead.first_touch_utm_campaign
    assert lead.first_touch_at.present?
    refute lead.provenance.key?("utm_campaign")

    lead.convert!
    deal = lead.reload.converted_deal
    assert_equal @campaign, deal.first_touch_campaign
    assert_equal lead.first_touch_at, deal.first_touch_at
    assert_equal "hero", deal.first_touch_utm_content
  end

  test "unknown UTM remains structured without inventing a campaign link" do
    post inquiry_path, params: { lead_inquiry: {
      name: "Unknown Source", email: "unknown.campaign@example.com",
      utm_source: "partner", utm_campaign: "not-configured"
    } }

    lead = Lead.order(:id).last
    assert_nil lead.first_touch_campaign
    assert_equal "partner", lead.first_touch_utm_source
    assert_equal "not-configured", lead.first_touch_utm_campaign
  end

  test "capture form supplies fallback campaign when UTM is absent" do
    form = LeadCaptureForm.create!(
      name: "Partner form", slug: "partner-form", active: true, campaign: @campaign,
      field_mapping: { "full_name" => "name", "work_email" => "email" }
    )

    post lead_capture_path(form.slug), params: { lead_inquiry: {
      fields: { full_name: "Partner Lead", work_email: "partner.lead@example.com" }
    } }

    assert_response :created
    assert_equal @campaign, Lead.order(:id).last.first_touch_campaign
  end
end
