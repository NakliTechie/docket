# One-way citation: a Deliverable summarizes a study WorkItem. Kept as a
# dedicated join (not a WorkLink) so citing a deliverable doesn't force the
# security-sensitive WorkLink::LINKABLE_TYPES allowlist to grow.
class DeliverableStudy < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :deliverable
  belongs_to :work_item, -> { with_deleted }

  validates :work_item_id, uniqueness: { scope: %i[tenant_id deliverable_id] }
  validates_same_tenant :deliverable, :work_item
end
