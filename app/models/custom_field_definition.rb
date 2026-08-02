class CustomFieldDefinition < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  RESOURCE_TYPES = %w[cases contacts leads deals work_items].freeze
  RESOURCE_FEATURES = {
    "cases" => "service_desk", "contacts" => "crm", "leads" => "crm",
    "deals" => "crm", "work_items" => "work"
  }.freeze
  MANAGE_PERMISSIONS = {
    "cases" => "queue:manage", "contacts" => "crm_config:manage", "leads" => "crm_config:manage",
    "deals" => "crm_config:manage", "work_items" => "project:manage"
  }.freeze
  READ_PERMISSIONS = {
    "cases" => "case:read", "contacts" => "contact:read", "leads" => "lead:read",
    "deals" => "deal:read", "work_items" => "work:read"
  }.freeze
  API_READ_SCOPES = {
    "cases" => "cases:read", "contacts" => "contacts:read", "leads" => "crm:read",
    "deals" => "crm:read", "work_items" => "work:read"
  }.freeze
  MODEL_NAMES = {
    "cases" => "Case", "contacts" => "Contact", "leads" => "Lead",
    "deals" => "Deal", "work_items" => "WorkItem"
  }.freeze
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

  def self.feature_for(resource_type) = RESOURCE_FEATURES.fetch(resource_type.to_s)
  def self.manage_permission_for(resource_type) = MANAGE_PERMISSIONS.fetch(resource_type.to_s)
  def self.read_permission_for(resource_type) = READ_PERMISSIONS.fetch(resource_type.to_s)
  def self.api_read_scope_for(resource_type) = API_READ_SCOPES.fetch(resource_type.to_s)
  def self.model_for(resource_type) = MODEL_NAMES.fetch(resource_type.to_s).constantize

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
