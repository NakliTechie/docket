require "test_helper"

class PriceBookTest < ActiveSupport::TestCase
  setup do
    @product = Product.create!(name: "Widget", sku: "W1", currency: "INR", default_unit_price_cents: 10_000)
    @book = PriceBook.create!(name: "Enterprise")
  end

  test "price_for returns the listed price, or nil when unlisted" do
    @book.price_book_entries.create!(product: @product, currency: "INR", unit_price_cents: 8_000)
    assert_equal 8_000, @book.price_for(@product, "INR")
    assert_nil @book.price_for(@product, "USD")
  end

  test "default creates and returns a singleton default book" do
    default = PriceBook.default
    assert default.is_default?
    assert_equal default, PriceBook.default
  end

  test "an entry is unique per book + product + currency" do
    @book.price_book_entries.create!(product: @product, currency: "INR", unit_price_cents: 8_000)
    refute @book.price_book_entries.build(product: @product, currency: "INR", unit_price_cents: 9_000).valid?
  end
end

class DealLineItemPricingTest < ActiveSupport::TestCase
  setup do
    @product = Product.create!(name: "Widget", sku: "W1", currency: "INR", default_unit_price_cents: 10_000)
    @book = PriceBook.create!(name: "Enterprise")
    @book.price_book_entries.create!(product: @product, currency: "INR", unit_price_cents: 8_000)
  end

  def deal(book: nil, name: "D")
    Deal.create!(name: name, pipeline: pipelines(:sales), currency: "INR", price_book: book,
                 contact: contacts(:asha), owner: users(:sales))
  end

  test "a line item resolves its price through the deal's price book" do
    item = deal(book: @book).deal_line_items.create!(product: @product, quantity: 1)
    assert_equal 8_000, item.unit_price_cents
  end

  test "falls back to the product default with no book" do
    item = deal(name: "D2").deal_line_items.create!(product: @product, quantity: 1)
    assert_equal 10_000, item.unit_price_cents
  end

  test "an explicit unit price is not overridden by the book" do
    item = deal(book: @book, name: "D3").deal_line_items.create!(product: @product, quantity: 1, unit_price_cents: 5_000)
    assert_equal 5_000, item.unit_price_cents
  end
end
