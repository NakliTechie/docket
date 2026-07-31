class Product < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :deal_line_items, dependent: :restrict_with_error

  validates :name, :sku, presence: true
  validates :sku, uniqueness: { scope: :tenant_id, case_sensitive: false,
                                conditions: -> { where(deleted_at: nil) } }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :default_unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                                       allow_nil: true

  normalizes :sku, with: ->(sku) { sku.to_s.strip.upcase }
  normalizes :currency, with: ->(currency) { currency.to_s.strip.upcase }

  scope :active, -> { where(active: true) }

  def default_unit_price
    default_unit_price_cents && default_unit_price_cents / 100.0
  end

  def default_unit_price=(amount)
    self.default_unit_price_cents = Cents.from(amount)
  end
end
