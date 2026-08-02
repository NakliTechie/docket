# A filed contest against a decision of record (see Decision#contestable?).
# Lifecycle: pending → overturned (the decision is reversed + dismissed) or
# denied (the decision stands). Driven through Decisioning::Dispatcher so the
# reversal rides the same audited gate as the decision itself.
class DecisionAppeal < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :decision
  belongs_to :appellant, class_name: "Contact", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  enum :status, { pending: 0, overturned: 1, denied: 2 }, prefix: true

  validates :grounds, presence: true
  validates :decision_id, uniqueness: { scope: :tenant_id, conditions: -> { status_pending } },
                          if: :status_pending?
  validates_same_tenant :decision, :appellant, :reviewed_by

  scope :recent_first, -> { order(id: :desc) }
end
