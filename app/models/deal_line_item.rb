class DealLineItem < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :deal
  belongs_to :product, -> { with_deleted }

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :product_id, uniqueness: { scope: %i[tenant_id deal_id] }
  validates_same_tenant :deal, :product
  validate :currency_matches_deal
  validate :product_currency_matches_deal

  before_validation :snapshot_product, on: :create
  after_save :recalculate_deal_total
  after_destroy :recalculate_deal_total

  def unit_price
    unit_price_cents && unit_price_cents / 100.0
  end

  def unit_price=(amount)
    self.unit_price_cents = Cents.from(amount)
  end

  def total_cents
    (BigDecimal(unit_price_cents.to_s) * quantity).round(0).to_i
  end

  private

  def snapshot_product
    return unless product

    self.description = product.name if description.blank?
    self.unit_price_cents = product.default_unit_price_cents if unit_price_cents.nil?
    self.currency = deal&.currency || product.currency if currency.blank?
  end

  def currency_matches_deal
    return if deal.nil? || currency.blank? || currency == deal.currency

    errors.add(:currency, "must match the deal currency")
  end

  def product_currency_matches_deal
    return if deal.nil? || product.nil? || product.currency == deal.currency

    errors.add(:product, "currency must match the deal currency")
  end

  def recalculate_deal_total
    return if deal.destroyed?

    deal.with_lock do
      deal.deal_line_items.reset
      deal.update!(value_cents: deal.deal_line_items.sum { |item| item.total_cents })
    end
  end
end
