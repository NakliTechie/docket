require "test_helper"

class QuotesPdfTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
  end

  test "renders a non-empty PDF with the line table and totals" do
    quote = Quote.create!(deal: @deal, currency: "INR")
    quote.quote_line_items.create!(description: "CNC machining", quantity: 2,
                                   unit_price_cents: 100_000, tax_rate: 18, hsn_sac: "998877")
    bytes = Quotes::Pdf.render(quote)
    assert bytes.start_with?("%PDF"), "output is a PDF document"
    assert_operator bytes.bytesize, :>, 1_000
  end

  test "renders a quote with a fractional quantity and no deliverable" do
    quote = Quote.create!(deal: @deal, currency: "INR")
    quote.quote_line_items.create!(description: "Bar stock", quantity: 1.5, unit_price_cents: 33_333, tax_rate: 12)
    bytes = Quotes::Pdf.render(quote)
    assert bytes.start_with?("%PDF")
  end

  test "renders a header-only quote (no lines) without raising" do
    quote = Quote.create!(deal: @deal, currency: "INR")
    assert Quotes::Pdf.render(quote).start_with?("%PDF")
  end
end
