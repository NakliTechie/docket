# PG11 — one product's unit price in a book, for a currency. Unique per
# (book, product, currency).
class PriceBookEntry < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :price_book
  belongs_to :product, -> { with_deleted }

  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :product_id, uniqueness: { scope: %i[tenant_id price_book_id currency] }
  validates_same_tenant :price_book, :product

  normalizes :currency, with: ->(currency) { currency.to_s.strip.upcase }

  def unit_price
    unit_price_cents && unit_price_cents / 100.0
  end

  def unit_price=(amount)
    self.unit_price_cents = Cents.from(amount)
  end
end
