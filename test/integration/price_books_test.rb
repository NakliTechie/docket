require "test_helper"

class PriceBooksTest < ActionDispatch::IntegrationTest
  test "a pipeline manager creates a book with entries, and cannot delete the default" do
    sign_in_as users(:client_admin)
    product = Product.create!(name: "Widget", sku: "W1", currency: "INR", default_unit_price_cents: 10_000)

    get price_books_path
    assert_response :success
    get new_price_book_path
    assert_response :success

    assert_difference "PriceBook.count", 1 do
      post price_books_path, params: { price_book: {
        name: "Enterprise",
        price_book_entries_attributes: {
          "0" => { product_id: product.id, currency: "INR", unit_price: "80" },
          "1" => { product_id: "", currency: "", unit_price: "" }
        }
      } }
    end
    book = PriceBook.find_by!(name: "Enterprise")
    assert_equal 1, book.price_book_entries.size, "the blank entry slot is dropped"
    assert_equal 8_000, book.price_book_entries.first.unit_price_cents

    default = PriceBook.default
    delete price_book_path(default)
    assert PriceBook.exists?(default.id), "the default book cannot be deleted"
  end

  test "a user without pipeline:manage is forbidden" do
    sign_in_as users(:sales)
    get price_books_path
    assert_response :forbidden
  end
end
