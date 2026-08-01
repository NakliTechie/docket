require "test_helper"

class QuotesFolioPayloadTest < ActiveSupport::TestCase
  setup do
    contacts(:asha).update!(external_id: "PARTY-123")
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
    @actor = users(:sales)
  end

  # A fixed-billing accepted quote: 2 × ₹1000 @ 18% = ₹2360 total.
  def accepted_quote(**line_attrs)
    quote = Quote.create!(deal: @deal, currency: "INR")
    quote.quote_line_items.create!({ description: "Machining", quantity: 2, unit_price_cents: 100_000,
                                     tax_rate: 18, hsn_sac: "998877" }.merge(line_attrs))
    Quotes.send!(quote, actor: @actor)
    Quotes.accept!(quote, actor: @actor)
    quote
  end

  test "only an accepted quote can be serialized" do
    draft = Quote.create!(deal: @deal, currency: "INR")
    assert_raises(Quotes::FolioPayload::Error) { Quotes::FolioPayload.build(draft) }
  end

  test "requires the contact to carry a folio party handle (external_id)" do
    quote = accepted_quote
    contacts(:asha).update!(external_id: nil)
    assert_raises(Quotes::FolioPayload::Error) { Quotes::FolioPayload.build(quote.reload) }
  end

  test "emits party, currency, tax-bearing lines, totals and a stable idempotency key" do
    quote = accepted_quote
    payload = Quotes::FolioPayload.build(quote)

    assert_equal "docket", payload[:source_system]
    assert_equal "PARTY-123", payload[:party_external_id]
    assert_equal "INR", payload[:currency]
    assert_equal "fixed", payload[:billing_type]
    assert_equal "docket:quote:#{quote.id}:v1:PARTY-123", payload[:idempotency_key]

    line = payload[:lines].sole
    assert_equal "998877", line[:hsn_sac]
    assert_equal 36_000, line[:tax_amount_cents]
    assert_equal 236_000, payload[:totals][:total_cents]
    assert_empty payload[:milestones]
  end

  test "milestone billing emits a schedule that reconciles exactly to the total" do
    quote = accepted_quote
    quote.update!(billing_type: :milestone) # total 236_000
    quote.quote_milestones.create!(name: "Advance", percentage: 50, position: 0)
    quote.quote_milestones.create!(name: "On delivery", percentage: 50, position: 1)

    payload = Quotes::FolioPayload.build(quote)
    amounts = payload[:milestones].map { |m| m[:amount_cents] }
    assert_equal 236_000, amounts.sum, "the schedule sums to the quote total"
    assert_equal [ "Advance", "On delivery" ], payload[:milestones].map { |m| m[:name] }
  end

  test "an unbalanced milestone schedule is refused" do
    quote = accepted_quote
    quote.update!(billing_type: :milestone)
    quote.quote_milestones.create!(name: "Partial", percentage: 40, position: 0)
    assert_raises(Quotes::FolioPayload::Error) { Quotes::FolioPayload.build(quote) }
  end

  test "a milestone quote with no schedule is refused" do
    quote = accepted_quote
    quote.update!(billing_type: :milestone)
    assert_raises(Quotes::FolioPayload::Error) { Quotes::FolioPayload.build(quote) }
  end

  # A percentage schedule can sum to 100% yet, on a tiny total, round so the
  # drift-absorbing last milestone would go negative — never emit that.
  test "a percentage schedule that resolves to a negative cent is refused" do
    quote = Quote.create!(deal: @deal, currency: "INR", billing_type: :milestone)
    quote.quote_line_items.create!(description: "Tiny", quantity: 1, unit_price_cents: 4, tax_rate: 0)
    Quotes.send!(quote, actor: @actor)
    Quotes.accept!(quote, actor: @actor)
    [ 40, 40, 15, 5 ].each_with_index do |pct, index|
      quote.quote_milestones.create!(name: "M#{index}", percentage: pct, position: index)
    end

    refute quote.milestones_balanced?, "overshoot on a 4-cent total is not billable"
    assert_raises(Quotes::FolioPayload::Error) { Quotes::FolioPayload.build(quote) }
  end
end
