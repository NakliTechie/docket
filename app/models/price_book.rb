# PG11 — a price book: per-product, per-currency unit prices. A deal picks a
# book; its line items resolve through it, falling back to the product's default
# price. One default book per tenant.
class PriceBook < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :price_book_entries, dependent: :destroy
  has_many :deals, dependent: :nullify
  accepts_nested_attributes_for :price_book_entries, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["product_id"].blank? }

  validates :name, presence: true,
                   uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }

  scope :active, -> { where(active: true) }

  # The tenant's default book, created on first use (preserves single-price).
  def self.default
    find_by(is_default: true) || create!(name: "Standard price book", is_default: true)
  end

  # The listed unit price for a product in a currency, or nil if not listed.
  def price_for(product, currency)
    price_book_entries.find_by(product_id: product.id, currency: currency)&.unit_price_cents
  end
end
