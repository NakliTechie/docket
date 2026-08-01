# A milestone on a milestone-billed Quote (Prithvi e2e, D-3). Carries exactly
# one of an explicit amount or a percentage of the quote total. The full
# schedule must reconcile to the quote total (Quote#milestones_balanced?);
# percentage schedules resolve to exact cents via Quote#milestone_amounts.
class QuoteMilestone < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :quote

  validates :name, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates_same_tenant :quote
  validate :exactly_one_of_amount_or_percentage

  def resolved_amount_cents(total_cents)
    return amount_cents if amount_cents.present?
    (BigDecimal(total_cents.to_s) * BigDecimal(percentage.to_s) / 100).round.to_i
  end

  private

  def exactly_one_of_amount_or_percentage
    present = [ amount_cents.present?, percentage.present? ].count(true)
    errors.add(:base, "a milestone needs exactly one of amount or percentage") unless present == 1
  end
end
