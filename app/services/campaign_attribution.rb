class CampaignAttribution
  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze
  CONTEXT_KEYS = %w[landing_page referrer].freeze

  def self.first_touch_attributes(values, fallback_campaign: nil, at: Time.current)
    source = values.to_h.stringify_keys
    captured = UTM_KEYS.index_with { |key| source[key].to_s.strip.presence }
    captured["landing_page"] = source["landing_page"].to_s.strip.presence
    captured["referrer"] = source["referrer"].to_s.strip.presence
    fallback = fallback_campaign if fallback_campaign&.attributable_on?(at.to_date)
    campaign = Campaign.matching_utm(captured["utm_campaign"], at: at.to_date) || fallback
    return {} if captured.values.compact.empty? && campaign.nil?

    {
      first_touch_campaign: campaign,
      first_touch_at: at,
      first_touch_utm_source: captured["utm_source"],
      first_touch_utm_medium: captured["utm_medium"],
      first_touch_utm_campaign: captured["utm_campaign"],
      first_touch_utm_term: captured["utm_term"],
      first_touch_utm_content: captured["utm_content"],
      first_touch_landing_page: captured["landing_page"],
      first_touch_referrer: captured["referrer"]
    }
  end
end
