# acts_as_tenant scopes READS, so another tenant's record is invisible — but an
# OPTIONAL `belongs_to` skips the existence check entirely, so mass-assigning a
# guessed id from another tenant was stored happily. The row then points at
# something nobody in this tenant can see: the association reads nil, and any
# later unscoped query (a report, an export, a notification) reads across the
# boundary.
#
#   validates_same_tenant :assignee, :reporter, :parent
#
# Compares tenant_id directly rather than loading the association, because the
# association is already scoped — `record.assignee` is nil for exactly the
# foreign row we are trying to catch.
module TenantReferentialIntegrity
  extend ActiveSupport::Concern

  class_methods do
    def validates_same_tenant(*names)
      validate do
        names.each do |name|
          foreign_id = public_send("#{name}_id")
          next if foreign_id.blank?

          klass = self.class.reflect_on_association(name).klass
          owner = ActsAsTenant.without_tenant { klass.unscoped.where(id: foreign_id).pick(:tenant_id) }
          next if owner.nil? || owner == tenant_id

          errors.add(name, :cross_tenant)
        end
      end
    end
  end
end
