class KnowledgeCategory < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  belongs_to :parent, -> { with_deleted }, class_name: "KnowledgeCategory", optional: true
  has_many :children, -> { order(:position, :name) }, class_name: "KnowledgeCategory",
           foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_many :reference_docs, dependent: nil

  validates :name, presence: true,
            uniqueness: { scope: %i[tenant_id parent_id], conditions: -> { where(deleted_at: nil) } }
  validates :slug, presence: true,
            uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates_same_tenant :parent
  validate :parent_is_not_self_or_descendant

  before_validation :assign_slug

  scope :roots, -> { where(parent_id: nil).order(:position, :name) }

  def ancestors
    chain = []
    node = parent
    seen = Set.new
    while node && seen.add?(node.id)
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

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

  def display_path
    (ancestors + [ self ]).map(&:name).join(" / ")
  end

  private

  def assign_slug
    return if slug.present? && !will_save_change_to_name?

    base = name.to_s.parameterize.presence || "category"
    candidate = base
    suffix = 1
    while self.class.where(slug: candidate).where.not(id: id).exists?
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end
    self.slug = candidate
  end

  def parent_is_not_self_or_descendant
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent, :invalid)
    elsif id.present? && parent&.ancestors&.map(&:id)&.include?(id)
      errors.add(:parent, :invalid)
    end
  end
end
