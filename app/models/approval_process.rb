# A maker-checker rule (PG4): an entry criterion that forces a second human to
# approve before the action takes effect. Two trigger types:
#   case_transition — guards a Case status change (trigger_key = target status,
#     e.g. "closed"): the case can't move there until an approver signs off.
#   effector_action — escalates a connector action (trigger_key = action key)
#     to human review, overriding the connector's auto-approve.
# One process per (trigger_type, trigger_key) per tenant.
class ApprovalProcess < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  has_many :approval_requests, dependent: :destroy

  enum :trigger_type, { case_transition: 0, effector_action: 1, work_item_transition: 2 },
       prefix: :trigger

  validates :name, presence: true
  validates :trigger_key, presence: true, uniqueness: { scope: [ :tenant_id, :trigger_type ] }
  validate :transition_key_is_a_real_status, if: :trigger_case_transition?
  validate :work_transition_key_is_valid, if: :trigger_work_item_transition?

  normalizes :trigger_key, with: ->(key) { key.to_s.strip.downcase }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:trigger_type, :trigger_key) }

  def self.for_transition(status)
    active.trigger_case_transition.find_by(trigger_key: status.to_s)
  end

  def self.for_action(key)
    active.trigger_effector_action.find_by(trigger_key: key.to_s)
  end

  def self.for_work_transition(item, state)
    active.trigger_work_item_transition.find_by(trigger_key: work_transition_key(item, state))
  end

  def self.work_transition_key(item, state)
    "#{item.project.key}:#{state.name}".downcase
  end

  private

  def transition_key_is_a_real_status
    return if Case.statuses.key?(trigger_key.to_s)
    errors.add(:trigger_key, :not_a_status)
  end

  def work_transition_key_is_valid
    return if trigger_key.to_s.match?(/\A[a-z][a-z0-9]{1,9}:.+\z/i)

    errors.add(:trigger_key, "must use PROJECT_KEY:State name")
  end
end
