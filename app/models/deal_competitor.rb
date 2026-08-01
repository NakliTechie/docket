class DealCompetitor < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity
  include HumanEnums

  humanizes_enums :disposition
  enum :disposition, { active: 0, lost_to: 1, won_against: 2 }, default: :active, prefix: true

  belongs_to :deal
  belongs_to :competitor, -> { with_deleted }

  validates :competitor_id, uniqueness: { scope: %i[tenant_id deal_id] }
  validates_same_tenant :deal, :competitor
end
