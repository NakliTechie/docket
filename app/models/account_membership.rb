class AccountMembership < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :organisation
  belongs_to :user

  validates :user_id, uniqueness: { scope: %i[tenant_id organisation_id] }
  validates_same_tenant :organisation, :user
end
