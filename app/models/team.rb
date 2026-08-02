class Team < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :team_memberships, dependent: nil
  has_many :members, through: :team_memberships, source: :user

  validates :name, presence: true,
                   uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
end
