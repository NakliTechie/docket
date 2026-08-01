require "test_helper"

class QuoteTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
  end

  def quote(**attrs)
    Quote.create!({ deal: @deal, currency: "INR" }.merge(attrs))
  end

  test "mints a per-tenant number and defaults to version 1 / draft" do
    q = quote
    assert q.number.present?
    assert_equal 1, q.version
    assert q.status_draft?
  end

  test "successive quotes get increasing numbers" do
    first = quote
    second = quote
    assert_operator second.number, :>, first.number
  end

  test "tax math is exact integer cents — 18% on ₹1000 × 2 = ₹360 tax, ₹2360 total" do
    q = quote
    q.quote_line_items.create!(description: "Machining", quantity: 2, unit_price_cents: 100_000, tax_rate: 18)
    assert_equal 200_000, q.subtotal_cents
    assert_equal 36_000, q.tax_cents
    assert_equal 236_000, q.total_cents
  end

  test "a fractional quantity rounds exactly (BigDecimal, no float drift)" do
    q = quote
    q.quote_line_items.create!(description: "Bar stock", quantity: 1.5, unit_price_cents: 33_333, tax_rate: 12)
    assert_equal 50_000, q.subtotal_cents          # 33_333 × 1.5 = 49_999.5 → 50_000 (half-up)
    assert_equal 6_000, q.tax_cents                # 12% of 50_000 = 6_000
  end

  test "line currency must match the quote" do
    q = quote
    line = q.quote_line_items.build(description: "X", quantity: 1, unit_price_cents: 100, currency: "USD")
    refute line.valid?
    assert_match(/match the quote currency/, line.errors[:currency].join)
  end

  test "tax_rate is bounded 0..100" do
    q = quote
    line = q.quote_line_items.build(description: "X", quantity: 1, unit_price_cents: 100, tax_rate: 150)
    refute line.valid?
  end

  test "an unissued deliverable cannot back a quote" do
    d = Deliverable.create!(deal: @deal, title: "Draft report",
                            scope_items: [ { "description" => "X" } ])
    q = Quote.new(deal: @deal, deliverable: d, currency: "INR")
    refute q.valid?
    assert_match(/issued/, q.errors[:deliverable].join)
  end

  test "currency locks once the quote has lines" do
    q = quote
    q.quote_line_items.create!(description: "X", quantity: 1, unit_price_cents: 100)
    q.currency = "USD"
    refute q.valid?
    assert_match(/cannot change/, q.errors[:currency].join)
  end

  test "human_status renders the localized label" do
    assert_equal "Draft", quote.human_status
  end
end
