# A pending/approved/rejected maker-checker request against a subject (PG4).
# Created when a guarded action is attempted; carries the checker's reasoned
# order (reason) once decided. Hash-chain audited like every decision of record.
class ApprovalRequest < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :approval_process
  belongs_to :subject, polymorphic: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }, prefix: :status

  validates :requested_action, presence: true, if: -> { approval_process&.trigger_case_transition? }

  scope :recent_first, -> { order(id: :desc) }

  def decided? = !status_pending?

  def subject_label
    case subject
    when Case then "#{subject.tracking_id} — #{subject.subject}"
    else subject.to_s
    end
  end
end
