require "test_helper"

class LeadScorecardTest < ActiveSupport::TestCase
  test "current returns a singleton, created with defaults" do
    card = LeadScorecard.current
    assert card.persisted?
    assert_equal 3, card.warm_threshold
    assert_equal 5, card.hot_threshold
    assert_equal %w[referral web_form], card.warm_source_list
    assert_equal card, LeadScorecard.current, "current is a singleton per tenant"
  end

  test "warm_source? is case-insensitive over the configured list" do
    card = LeadScorecard.new(warm_sources: "Referral, WEB_FORM")
    assert card.warm_source?("referral")
    assert card.warm_source?("web_form")
    refute card.warm_source?("manual")
  end

  test "hot threshold must be at or above warm" do
    refute LeadScorecard.new(warm_threshold: 4, hot_threshold: 2).valid?
    assert LeadScorecard.new(warm_threshold: 2, hot_threshold: 4).valid?
  end

  test "weights must be non-negative integers" do
    refute LeadScorecard.new(weight_email: -1).valid?
  end
end
