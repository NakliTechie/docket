class Competitor < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :deal_competitors, dependent: :restrict_with_error
  has_many :deals, through: :deal_competitors

  validates :name, presence: true,
                   uniqueness: { scope: :tenant_id, case_sensitive: false,
                                 conditions: -> { where(deleted_at: nil) } }
  validates :website, format: { with: %r{\Ahttps?://[^\s]+\z}i }, allow_blank: true
end
