# A price quote derived from an issued Deliverable (Prithvi e2e, Phase 1).
# Versioned: revising a quote mints a new row that shares +number+, bumps
# +version+, and points at the quote it +supersedes+ (revisions are tracked,
# never overwritten). Money is summed from the lines in integer cents; tax and
# HSN/SAC live on QuoteLineItem — the deliverable stays price/tax-free.
class Quote < ApplicationRecord
  Error = Class.new(StandardError)

  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums
  include TenantReferentialIntegrity

  humanizes_enums :status

  enum :status, { draft: 0, sent: 1, accepted: 2, rejected: 3, expired: 4 }, default: :draft, prefix: :status
  # How an accepted quote bills downstream: one invoice, or a milestone schedule.
  enum :billing_type, { fixed: 0, milestone: 1 }, default: :fixed, prefix: :billing_type

  belongs_to :deal
  belongs_to :deliverable, optional: true
  belongs_to :supersedes, class_name: "Quote", optional: true
  has_one :superseded_by, class_name: "Quote", foreign_key: :supersedes_id, inverse_of: :supersedes,
                          dependent: nil

  has_many :quote_line_items, -> { order(:position, :id) }, dependent: :destroy
  has_many :quote_milestones, -> { order(:position, :id) }, dependent: :destroy
  has_many :audit_entries, as: :auditable, dependent: nil

  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :number, presence: true,
                     uniqueness: { scope: %i[tenant_id version], conditions: -> { where(deleted_at: nil) } }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates_same_tenant :deal, :deliverable
  validate :deliverable_is_issued_on_this_deal
  validate :currency_is_locked_by_line_items, on: :update

  normalizes :currency, with: ->(currency) { currency.to_s.strip.upcase }

  before_validation :assign_number, on: :create

  # Stable-across-revisions human handle (revision suffix distinguishes versions).
  def reference = "Q-#{number}-r#{version}"

  def subtotal_cents = quote_line_items.sum(&:subtotal_cents)
  def tax_cents = quote_line_items.sum(&:tax_amount_cents)
  def total_cents = quote_line_items.sum(&:total_cents)

  # The freshest version — nothing supersedes it. Acceptance operates only here.
  def latest? = superseded_by.nil?

  # Resolve the milestone schedule to explicit cents. The LAST milestone absorbs
  # any rounding drift, so a balanced schedule (see #milestones_balanced?) always
  # reconciles to the exact total. Returns { milestone_id => cents }.
  def milestone_amounts
    milestones = quote_milestones.to_a
    return {} if milestones.empty?

    total = total_cents
    running = 0
    result = {}
    milestones.each_with_index do |milestone, index|
      amount = index == milestones.length - 1 ? total - running : milestone.resolved_amount_cents(total)
      running += amount
      result[milestone.id] = amount
    end
    result
  end

  # A schedule is coherent when it is single-kind and reconciles: all-amount
  # milestones must sum to the total; all-percentage must sum to 100%.
  def milestones_balanced?
    milestones = quote_milestones.to_a
    return true if milestones.empty?

    kinds = milestones.map { |milestone| milestone.amount_cents.present? ? :amount : :percentage }.uniq
    return false unless kinds.length == 1

    if kinds.first == :amount
      milestones.sum { |milestone| milestone.amount_cents.to_i } == total_cents
    else
      milestones.sum { |milestone| milestone.percentage.to_d } == 100
    end
  end

  private

  def assign_number
    self.number ||= (self.class.unscoped.where(tenant_id: tenant_id).maximum(:number) || 1000) + 1
  end

  def deliverable_is_issued_on_this_deal
    return if deliverable.nil?
    errors.add(:deliverable, "must be issued before it can be quoted") unless deliverable.status_issued?
    errors.add(:deliverable, "must belong to the quote's deal") if deliverable.deal_id != deal_id
  end

  def currency_is_locked_by_line_items
    return unless will_save_change_to_currency? && quote_line_items.exists?
    errors.add(:currency, "cannot change while the quote has line items")
  end
end
