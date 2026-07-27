# Ties a work item to the customer-facing record it came from or serves. This is
# what makes Docket one product rather than three that share a login: a case
# escalates into engineering work, a won deal spawns an onboarding project, and
# each side can see the other.
class WorkLink < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include HumanEnums
  include TenantReferentialIntegrity

  humanizes_enums :relation

  LINKABLE_TYPES = %w[Case Deal Lead Contact].freeze

  enum :relation, { escalated_from: 0, related_to: 1, onboarding_for: 2 },
       default: :related_to, prefix: true

  belongs_to :work_item
  belongs_to :linkable, polymorphic: true
  belongs_to :created_by, -> { with_deleted }, class_name: "User", optional: true

  validates :linkable_type, inclusion: { in: LINKABLE_TYPES }
  validates :work_item_id, uniqueness: { scope: %i[linkable_type linkable_id] }
  validates_same_tenant :work_item
  # linkable is polymorphic, so the helper's reflection trick does not apply —
  # and this is the one that leaks CONTENT (the linked case's subject and body),
  # not just an integrity break.
  validate :linkable_is_same_tenant

  def display_label = "#{work_item&.reference} ↔ #{linkable_type}##{linkable_id}"

  private

  def linkable_is_same_tenant
    return if linkable_id.blank? || linkable_type.blank?
    return unless LINKABLE_TYPES.include?(linkable_type)

    owner = ActsAsTenant.without_tenant do
      linkable_type.constantize.unscoped.where(id: linkable_id).pick(:tenant_id)
    end
    errors.add(:linkable, :cross_tenant) if owner.present? && owner != tenant_id
  end
end
