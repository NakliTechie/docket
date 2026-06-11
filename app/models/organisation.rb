class Organisation < ApplicationRecord
  include SoftDeletable
  include Audited

  KINDS = %w[department branch company other].freeze

  def human_kind
    kind.blank? ? "" : I18n.t("organisations.enum.kind.#{kind}")
  end

  has_many :contacts, dependent: nil

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :kind, inclusion: { in: KINDS }
end
