# A persisted decisioning proposal — the history + contestability trail. Created
# by Decisioning::Dispatcher from a rule's Decisioning::Decision, then moved
# through its lifecycle: proposed → applied (autonomous auto-applies; confirm /
# of_record apply only after a human approves) or → rejected. Hash-chain audited
# like every other mutation, so the who/why of each decision is tamper-evident.
class Decision < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :subject, polymorphic: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :appeals, class_name: "DecisionAppeal", dependent: :destroy

  enum :status, { proposed: 0, applied: 1, dismissed: 2, rejected: 3 }, prefix: true

  validates :rule, :version, :signal, :decision_class, presence: true

  scope :recent_first, -> { order(id: :desc) }
  # Parked decisions that need a human before they can act (confirm / of_record).
  scope :awaiting_confirmation, -> { status_proposed.where.not(decision_class: "autonomous") }

  # Customer visibility is deliberately narrower than staff visibility. Only
  # decisions directly concerning the signed-in contact or one of their cases
  # enter the portal; internal CRM records stay private.
  scope :concerning, ->(contact) {
    direct = where(subject_type: "Contact", subject_id: contact.id)
    case_decisions = where(subject_type: "Case", subject_id: contact.cases.select(:id))
    direct.or(case_decisions)
  }

  def autonomous? = decision_class == "autonomous"
  def of_record? = decision_class == "of_record"

  # A decision of record is contestable through the appeal path; it always
  # carries a human approver + a reasoned order once acted on.
  def contestable? = of_record?

  # Appealable once it has actually acted (applied) and is contestable.
  def appealable? = contestable? && status_applied?

  def open_appeal = appeals.status_pending.recent_first.first
end
