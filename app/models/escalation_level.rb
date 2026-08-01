# One tier of an EscalationRule (PG3): after +after_minutes+ past the rule's
# reference time, reassign the case (then_assignee) and/or alert someone
# (notify_user). At least one action is required.
class EscalationLevel < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :escalation_rule
  belongs_to :then_assignee, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :notify_user, -> { with_deleted }, class_name: "User", optional: true
  has_many :escalation_executions, dependent: :destroy

  validates :after_minutes,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 525_600 }
  validates_same_tenant :escalation_rule, :then_assignee, :notify_user
  validate :has_an_action

  private

  def has_an_action
    return if then_assignee_id.present? || notify_user_id.present?
    errors.add(:base, :needs_action)
  end
end
