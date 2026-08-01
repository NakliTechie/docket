# A priced line on a Quote. This is where tax lives: HSN/SAC classification +
# a tax rate produce a tax amount — 100% greenfield, deliberately separate from
# DealLineItem (catalog selling) so tax is never retrofitted onto the catalog.
# Money math is integer cents via BigDecimal, so no binary-float drift.
class QuoteLineItem < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :quote

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates_same_tenant :quote
  validate :currency_matches_quote

  before_validation :inherit_currency, on: :create

  def unit_price
    unit_price_cents && unit_price_cents / 100.0
  end

  def unit_price=(amount)
    self.unit_price_cents = Cents.from(amount)
  end

  # qty × unit price, in whole cents (BigDecimal so a fractional qty rounds
  # exactly, like DealLineItem#total_cents).
  def subtotal_cents
    (BigDecimal(unit_price_cents.to_s) * quantity).round.to_i
  end

  def tax_amount_cents
    (BigDecimal(subtotal_cents.to_s) * BigDecimal(tax_rate.to_s) / 100).round.to_i
  end

  def total_cents
    subtotal_cents + tax_amount_cents
  end

  private

  def inherit_currency
    self.currency = quote.currency if currency.blank? && quote
  end

  def currency_matches_quote
    return if quote.nil? || currency.blank? || currency == quote.currency
    errors.add(:currency, "must match the quote currency")
  end
end
