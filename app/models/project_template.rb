class ProjectTemplate < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  KEY_FORMAT = Project::KEY_FORMAT

  has_many :project_template_items, -> { order(:position, :id) }, dependent: :destroy,
           inverse_of: :project_template
  has_many :projects, dependent: :nullify
  accepts_nested_attributes_for :project_template_items, allow_destroy: true,
                                reject_if: ->(attributes) { attributes["title"].blank? }

  validates :name, presence: true,
                   uniqueness: { scope: :tenant_id, case_sensitive: false }
  validates :key_prefix, presence: true, format: { with: KEY_FORMAT }

  normalizes :key_prefix, with: ->(key) { key.to_s.strip.upcase }

  scope :active, -> { where(active: true) }
end
