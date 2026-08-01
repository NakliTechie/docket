# PG8 — the role a contact plays on a deal (the Salesforce "contact roles"
# parity gap). One role per contact per deal. Mirrors DealCompetitor.
class DealContactRole < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity
  include HumanEnums

  humanizes_enums :role

  enum :role, { decision_maker: 0, economic_buyer: 1, champion: 2, influencer: 3, technical: 4, other: 5 },
       default: :influencer, prefix: :role

  belongs_to :deal
  belongs_to :contact, -> { with_deleted }

  validates :contact_id, uniqueness: { scope: %i[tenant_id deal_id] }
  validates_same_tenant :deal, :contact
end
