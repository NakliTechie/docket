class TeamMembership < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :team
  belongs_to :user

  validates :user_id, uniqueness: { scope: %i[tenant_id team_id] }
  validates_same_tenant :team, :user
end
