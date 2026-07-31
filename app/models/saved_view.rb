class SavedView < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  RESOURCE_FILTERS = {
    "cases" => %w[q status priority queue_id assignee_id sort dir],
    "work_items" => %w[q assignee_id kind state_id open]
  }.freeze

  belongs_to :user, -> { with_deleted }

  validates :name, presence: true, length: { maximum: 80 },
                   uniqueness: { scope: %i[tenant_id user_id resource_type context_id],
                                 case_sensitive: false }
  validates :resource_type, inclusion: { in: RESOURCE_FILTERS.keys }
  validates_same_tenant :user
  validate :context_matches_resource
  validate :filters_match_resource

  normalizes :name, with: ->(name) { name.to_s.strip }

  scope :for_resource, ->(resource_type, context_id: nil) {
    where(resource_type: resource_type, context_id: context_id)
  }

  def self.sanitize_filters(resource_type, input)
    allowed = RESOURCE_FILTERS.fetch(resource_type.to_s, [])
    source = input.respond_to?(:permit) ? input.permit(*allowed).to_h : input.to_h
    source.stringify_keys.slice(*allowed).transform_values(&:to_s).reject { |_, value| value.blank? }
  end

  private

  def context_matches_resource
    errors.add(:context_id, "must be blank for cases") if resource_type == "cases" && context_id.present?
    return unless resource_type == "work_items"

    if context_id.blank?
      errors.add(:context_id, "is required for work items")
    elsif !Project.unscoped.exists?(id: context_id, tenant_id: tenant_id)
      errors.add(:context_id, "must reference a project in the same tenant")
    end
  end

  def filters_match_resource
    return unless RESOURCE_FILTERS.key?(resource_type)

    unknown = filters.to_h.keys.map(&:to_s) - RESOURCE_FILTERS.fetch(resource_type)
    errors.add(:filters, "contain unsupported keys: #{unknown.join(', ')}") if unknown.any?
  end
end
