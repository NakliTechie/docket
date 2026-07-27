# Who gets told when a work item moves. A join, not a subscription engine —
# notification delivery lands in WM4.
class WorkWatch < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :work_item
  belongs_to :user, -> { with_deleted }

  validates :user_id, uniqueness: { scope: :work_item_id }

  def display_label = "watch on #{work_item&.reference}"
end
