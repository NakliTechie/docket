class LeadCaptureForm < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :campaign, -> { with_deleted }, optional: true

  TARGET_FIELDS = %w[name email phone company_name notes].freeze
  DEFAULT_MAPPING = {
    "name" => "name", "email" => "email", "phone" => "phone",
    "company_name" => "company_name", "message" => "notes"
  }.freeze

  validates :name, :slug, presence: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ },
                   uniqueness: { scope: :tenant_id }
  validate :mapping_is_valid

  normalizes :slug, with: ->(slug) { slug.to_s.strip.downcase.tr("_ ", "-") }

  before_save :unset_other_defaults, if: :is_default?

  scope :active, -> { where(active: true) }

  def mapping
    field_mapping.presence || DEFAULT_MAPPING
  end

  def self.default_form
    active.find_by(is_default: true) || active.order(:id).first
  end

  def map_fields(values)
    source = values.to_h.stringify_keys
    mapping.each_with_object({}) do |(input_name, lead_field), attributes|
      attributes[lead_field] = source[input_name.to_s]
    end
  end

  private

  def mapping_is_valid
    mapping_hash = field_mapping.to_h
    if mapping_hash.blank?
      errors.add(:field_mapping, "must map at least a name and an email or phone")
      return
    end
    if mapping_hash.keys.any? { |key| !key.to_s.match?(/\A[a-z][a-z0-9_]*\z/) }
      errors.add(:field_mapping, "source names must use lowercase letters, numbers, and underscores")
    end
    values = mapping_hash.values.map(&:to_s)
    errors.add(:field_mapping, "contains an unsupported target") if (values - TARGET_FIELDS).any?
    errors.add(:field_mapping, "must include name") unless values.include?("name")
    errors.add(:field_mapping, "must include email or phone") unless (values & %w[email phone]).any?
    errors.add(:field_mapping, "cannot map two inputs to one target") unless values.uniq.size == values.size
  end

  def unset_other_defaults
    self.class.where.not(id: id).where(is_default: true).find_each do |other_form|
      other_form.update!(is_default: false)
    end
  end
end
