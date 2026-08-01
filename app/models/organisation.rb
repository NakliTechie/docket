class Organisation < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include TenantReferentialIntegrity

  KINDS = %w[department branch company other].freeze

  def human_kind
    kind.blank? ? "" : I18n.t("organisations.enum.kind.#{kind}")
  end

  has_many :contacts, dependent: nil
  has_many :cases, through: :contacts
  has_many :deals, dependent: :nullify
  # PG9 — account hierarchy (self-referential).
  belongs_to :parent, -> { with_deleted }, class_name: "Organisation", optional: true
  has_many :children, class_name: "Organisation", foreign_key: :parent_id, dependent: :nullify,
                      inverse_of: :parent

  validates :name, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :kind, inclusion: { in: KINDS }
  validates_same_tenant :parent
  validate :parent_is_not_self_or_descendant

  def root? = parent_id.nil?

  # Parent chain from the immediate parent upward (cycle-safe).
  def ancestors
    chain = []
    node = parent
    seen = Set.new
    while node && seen.add?(node.id)
      chain << node
      node = node.parent
    end
    chain
  end

  # This account plus every sub-account beneath it (cycle-safe BFS).
  def self_and_descendants
    collected = [ self ]
    seen = Set.new([ id ])
    queue = children.to_a
    until queue.empty?
      node = queue.shift
      next unless seen.add?(node.id)
      collected << node
      queue.concat(node.children.to_a)
    end
    collected
  end

  # Rollups across the account and its sub-accounts (PG9b).
  def deals_including_descendants
    Deal.where(organisation_id: self_and_descendants.map(&:id))
  end

  def cases_including_descendants
    Case.joins(:contact).where(contacts: { organisation_id: self_and_descendants.map(&:id) })
  end

  private

  def parent_is_not_self_or_descendant
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent, "cannot be the account itself")
    elsif id.present? && parent && parent.ancestors.map(&:id).include?(id)
      errors.add(:parent, "cannot be one of this account's sub-accounts (would create a loop)")
    end
  end
end
