require "test_helper"

class QuoteMilestoneTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
    @quote = Quote.create!(deal: @deal, currency: "INR")
    @quote.quote_line_items.create!(description: "Machining", quantity: 1, unit_price_cents: 100_000, tax_rate: 0)
  end

  test "requires exactly one of amount or percentage" do
    milestone = @quote.quote_milestones.build(name: "Advance")
    refute milestone.valid?, "neither set is invalid"

    milestone.amount_cents = 50_000
    milestone.percentage = 50
    refute milestone.valid?, "both set is invalid"

    milestone.percentage = nil
    assert milestone.valid?, "exactly one set is valid"
  end

  test "resolved_amount_cents uses the explicit amount or the percentage of the total" do
    amount_milestone = @quote.quote_milestones.create!(name: "Advance", amount_cents: 40_000)
    percentage_milestone = @quote.quote_milestones.build(name: "On delivery", percentage: 60)

    assert_equal 40_000, amount_milestone.resolved_amount_cents(100_000)
    assert_equal 60_000, percentage_milestone.resolved_amount_cents(100_000)
  end

  test "percentage is bounded 0..100" do
    refute @quote.quote_milestones.build(name: "Too much", percentage: 150).valid?
  end
end
