class CustomFieldDefinition < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  RESOURCE_TYPES = %w[cases work_items].freeze
  FIELD_TYPES = %w[short_text long_text integer decimal boolean date single_select multi_select].freeze
  SELECT_TYPES = %w[single_select multi_select].freeze

  enum :field_type, FIELD_TYPES.index_with(&:itself), prefix: true

  validates :resource_type, inclusion: { in: RESOURCE_TYPES }
  validates :key, presence: true, format: { with: /\A[a-z][a-z0-9_]{1,49}\z/ },
                  uniqueness: { scope: %i[tenant_id resource_type], case_sensitive: false }
  validates :label, presence: true, length: { maximum: 80 },
                    uniqueness: { scope: %i[tenant_id resource_type], case_sensitive: false }
  validates :field_type, inclusion: { in: FIELD_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :key_is_immutable
  validate :options_match_type

  normalizes :key, with: ->(key) { key.to_s.strip.downcase.gsub(/[^a-z0-9_]/, "_") }
  normalizes :label, with: ->(label) { label.to_s.strip }

  before_validation :normalize_options
  before_validation :assign_position, on: :create

  scope :for_resource, ->(resource_type) { where(resource_type: resource_type.to_s) }
  scope :active, -> { where(active: true) }
  scope :reportable, -> { where(reportable: true) }
  scope :ordered, -> { order(:position, :id) }

  def select_type? = SELECT_TYPES.include?(field_type)

  private

  def normalize_options
    self.options = Array(options).map { |option| option.to_s.strip }.reject(&:blank?).uniq
    self.options = [] unless select_type?
  end

  def assign_position
    return if position.to_i.positive?

    self.position = (self.class.for_resource(resource_type).maximum(:position) || -1) + 1
  end

  def key_is_immutable
    errors.add(:key, :immutable) if persisted? && will_save_change_to_key?
  end

  def options_match_type
    if select_type?
      errors.add(:options, :blank) if options.empty?
      errors.add(:options, :too_many) if options.size > 100
      errors.add(:options, :too_long) if options.any? { |option| option.length > 100 }
    elsif options.any?
      errors.add(:options, :not_allowed)
    end
  end
end
