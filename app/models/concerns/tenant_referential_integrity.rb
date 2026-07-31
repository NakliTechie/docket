# Tenant scopes protect reads, but they do not make a foreign key safe. An
# optional `belongs_to` can otherwise store a guessed id from another tenant;
# the scoped association then reads as nil while unscoped jobs and exports can
# still cross the boundary.
#
# This concern is installed on ApplicationRecord so coverage is derived from
# the model's `belongs_to` reflections. `validates_same_tenant` remains as an
# executable declaration for especially sensitive relationships, but callers
# do not have to remember to enumerate every new association.
module TenantReferentialIntegrity
  extend ActiveSupport::Concern

  included do
    class_attribute :declared_same_tenant_associations,
                    instance_accessor: false,
                    default: []
    class_attribute :cross_tenant_association_exceptions,
                    instance_accessor: false,
                    default: []
    validate :tenant_associations_share_tenant
  end

  class_methods do
    def validates_same_tenant(*names)
      self.declared_same_tenant_associations |= names.map(&:to_sym)
    end

    # An intentional exception must be declared on the owning model. This is
    # reserved for attribution/history edges, never business-data ownership.
    def allows_cross_tenant_association(*names)
      self.cross_tenant_association_exceptions |= names.map(&:to_sym)
    end
  end

  private

  def tenant_associations_share_tenant
    references = tenant_references
    return if references.empty?

    expected_tenant_id = tenant_integrity_baseline(references)
    return if expected_tenant_id.blank?

    references.each do |name, owner_tenant_id|
      next if owner_tenant_id.blank? || owner_tenant_id == expected_tenant_id
      next if errors.details[name].any? { |detail| detail[:error] == :cross_tenant }

      errors.add(name, :cross_tenant)
    end
  end

  def tenant_integrity_baseline(references)
    return self[:tenant_id] if has_attribute?(:tenant_id) && self[:tenant_id].present?

    # Join/child records without their own tenant column inherit tenancy from
    # their associations. Comparing those referenced owners to one another
    # catches mixed-tenant joins without coupling global records (Session,
    # ApiToken) to whatever ambient tenant happens to be present when saved.
    references.values.compact.first
  end

  def tenant_references
    self.class.reflect_on_all_associations(:belongs_to).each_with_object({}) do |reflection, owners|
      next if reflection.name == :tenant
      next if self.class.cross_tenant_association_exceptions.include?(reflection.name)

      foreign_id = self[reflection.foreign_key]
      next if foreign_id.blank?

      target_class = tenant_reference_class(reflection)
      next unless target_class&.<(ApplicationRecord)
      next unless target_class.column_names.include?("tenant_id")

      owner_tenant_id = ActsAsTenant.without_tenant do
        target_class.unscoped.where(target_class.primary_key => foreign_id).pick(:tenant_id)
      end
      owners[reflection.name] = owner_tenant_id if owner_tenant_id.present?
    end
  end

  def tenant_reference_class(reflection)
    if reflection.polymorphic?
      self[reflection.foreign_type].to_s.safe_constantize
    else
      reflection.klass
    end
  rescue NameError
    nil
  end
end
