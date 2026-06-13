# A named sales funnel — an ordered set of stages that deals move
# through on the kanban board (v1.2 CRM). Admin-managed, like queues.
class Pipeline < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :pipeline_stages, -> { order(:position) }, dependent: nil, inverse_of: :pipeline
  has_many :deals, dependent: nil

  accepts_nested_attributes_for :pipeline_stages, allow_destroy: true

  before_validation :ensure_slug, on: :create

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validate :has_at_least_one_stage

  scope :active, -> { where(active: true) }

  # The pipeline new deals land in by default — the first active one.
  def self.default
    active.order(:position, :id).first
  end

  def first_stage
    pipeline_stages.min_by(&:position)
  end

  private

  def ensure_slug
    self.slug = name.to_s.parameterize if slug.blank?
  end

  def has_at_least_one_stage
    errors.add(:base, :no_stages) if pipeline_stages.reject(&:marked_for_destruction?).empty?
  end
end
