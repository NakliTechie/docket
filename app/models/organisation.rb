class Organisation < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  KINDS = %w[department branch company other].freeze

  def human_kind
    kind.blank? ? "" : I18n.t("organisations.enum.kind.#{kind}")
  end

  has_many :contacts, dependent: nil

  validates :name, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :kind, inclusion: { in: KINDS }
end
