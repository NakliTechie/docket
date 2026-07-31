class WorkItemRelation < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  RELATION_TYPES = %w[blocks duplicates].freeze

  belongs_to :source, class_name: "WorkItem"
  belongs_to :target, class_name: "WorkItem"
  belongs_to :created_by, -> { with_deleted }, class_name: "User", optional: true

  validates :relation_type, inclusion: { in: RELATION_TYPES }
  validates :source_id, uniqueness: { scope: %i[tenant_id target_id relation_type] }
  validate :items_are_distinct
  validates_same_tenant :source, :target, :created_by

  before_validation :canonicalize_duplicate_pair

  def display_label = "#{source&.reference} #{relation_type} #{target&.reference}"

  private

  def canonicalize_duplicate_pair
    return unless relation_type == "duplicates" && source_id && target_id && source_id > target_id

    original_source = source
    original_target = target
    self.source = original_target
    self.target = original_source
  end

  def items_are_distinct
    errors.add(:target, :same_item) if source_id.present? && source_id == target_id
  end
end
