# A comment on a work item. Deliberately NOT the service desk's Message: a
# Message carries channel, direction, public-vs-internal and customer delivery
# semantics that make no sense on an internal work item. Overloading it would
# make both models lie.
class WorkComment < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  belongs_to :work_item
  belongs_to :author, -> { with_deleted }, class_name: "User"

  has_many :audit_entries, as: :auditable, dependent: nil

  validates :body, presence: true

  def display_label = "comment on #{work_item&.reference}"
end
