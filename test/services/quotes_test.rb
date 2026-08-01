require "test_helper"

class QuotesTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
    @actor = users(:sales)
  end

  # An issued deliverable to seed quotes from.
  def issued_deliverable
    d = Deliverable.create!(deal: @deal, title: "Feasibility report",
                            scope_items: [ { "description" => "Machine 20 brackets", "quantity" => 20, "unit" => "pcs" },
                                          { "description" => "Heat treatment", "quantity" => 1, "unit" => "lot" } ])
    Deliverables.submit_for_review!(d, by: users(:sales))
    Deliverables.approve!(d, by: users(:supervisor), reason: "Approved.")
    Deliverables.issue!(d, by: users(:supervisor))
    d
  end

  test "build_from_deliverable derives one draft line per scope entry, currency locked" do
    quote = Quotes.build_from_deliverable(issued_deliverable, currency: "INR", actor: @actor)
    assert quote.status_draft?
    assert_equal "INR", quote.currency
    assert_equal [ "Machine 20 brackets", "Heat treatment" ], quote.quote_line_items.map(&:description)
    assert_equal [ 20, 1 ], quote.quote_line_items.map { |l| l.quantity.to_i }
    assert quote.quote_line_items.all? { |l| l.unit_price_cents.zero? }, "prices left for the quoter to fill"
  end

  test "build_from_deliverable refuses an unissued deliverable" do
    draft = Deliverable.create!(deal: @deal, title: "Draft", scope_items: [ { "description" => "X" } ])
    assert_raises(Quote::Error) { Quotes.build_from_deliverable(draft, currency: "INR", actor: @actor) }
  end

  test "send requires at least one line" do
    empty = Quote.create!(deal: @deal, currency: "INR")
    assert_raises(Quote::Error) { Quotes.send!(empty, actor: @actor) }
  end

  test "accepting a sent quote advances the deal to won so onboarding can fire" do
    quote = Quotes.build_from_deliverable(issued_deliverable, currency: "INR", actor: @actor)
    quote.quote_line_items.first.update!(unit_price_cents: 100_000, tax_rate: 18)
    Quotes.send!(quote, actor: @actor)

    refute @deal.reload.status_won?
    Quotes.accept!(quote, actor: @actor)

    assert quote.status_accepted?
    assert quote.accepted_at.present?
    assert @deal.reload.status_won?, "the deal is won, so DealOnboarding may run"
  end

  test "only a sent quote can be accepted" do
    quote = Quote.create!(deal: @deal, currency: "INR")
    assert_raises(Quote::Error) { Quotes.accept!(quote, actor: @actor) }
  end

  test "rejecting records the reason and leaves the deal open" do
    quote = Quotes.build_from_deliverable(issued_deliverable, currency: "INR", actor: @actor)
    Quotes.send!(quote, actor: @actor)
    Quotes.reject!(quote, actor: @actor, reason: "Price too high")

    assert quote.status_rejected?
    assert_equal "Price too high", quote.rejection_reason
    refute @deal.reload.status_won?
  end

  test "revise mints a new version sharing the number, superseding the prior, copying lines" do
    quote = Quotes.build_from_deliverable(issued_deliverable, currency: "INR", actor: @actor)
    quote.quote_line_items.first.update!(unit_price_cents: 100_000, tax_rate: 18)
    Quotes.send!(quote, actor: @actor)

    revision = Quotes.revise!(quote, actor: @actor)
    assert_equal quote.number, revision.number
    assert_equal 2, revision.version
    assert_equal quote, revision.supersedes
    assert revision.status_draft?
    assert_equal quote.quote_line_items.map(&:description), revision.quote_line_items.map(&:description)
    assert_equal 100_000, revision.quote_line_items.first.unit_price_cents
  end

  test "a superseded quote cannot be accepted — only the latest version" do
    quote = Quotes.build_from_deliverable(issued_deliverable, currency: "INR", actor: @actor)
    quote.quote_line_items.first.update!(unit_price_cents: 100_000)
    Quotes.send!(quote, actor: @actor)
    Quotes.revise!(quote, actor: @actor)

    error = assert_raises(Quote::Error) { Quotes.accept!(quote.reload, actor: @actor) }
    assert_match(/superseded/, error.message)
  end

  test "an accepted quote cannot be revised" do
    quote = Quotes.build_from_deliverable(issued_deliverable, currency: "INR", actor: @actor)
    quote.quote_line_items.first.update!(unit_price_cents: 100_000)
    Quotes.send!(quote, actor: @actor)
    Quotes.accept!(quote, actor: @actor)
    assert_raises(Quote::Error) { Quotes.revise!(quote, actor: @actor) }
  end
end
