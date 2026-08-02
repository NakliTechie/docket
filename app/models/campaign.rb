class Campaign < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :status, :channel

  enum :status, { draft: 0, active: 1, completed: 2, archived: 3 }, default: :draft, prefix: true
  enum :channel, {
    email: 0, paid_search: 1, social: 2, event: 3, referral: 4, other: 5
  }, default: :other, prefix: true

  has_many :attributed_leads, class_name: "Lead", foreign_key: :first_touch_campaign_id,
                               dependent: nil, inverse_of: :first_touch_campaign
  has_many :attributed_deals, class_name: "Deal", foreign_key: :first_touch_campaign_id,
                               dependent: nil, inverse_of: :first_touch_campaign
  has_many :lead_capture_forms, dependent: :nullify

  normalizes :code, with: ->(value) { value.to_s.strip.downcase.tr("_ ", "-") }
  normalizes :utm_source, :utm_medium, :utm_campaign,
             with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :currency, with: ->(value) { value.to_s.strip.upcase }

  validates :name, :code, :utm_campaign, presence: true
  validates :name, length: { maximum: 200 }
  validates :code, length: { maximum: 100 }
  validates :utm_source, :utm_medium, :utm_campaign, length: { maximum: 255 }
  validates :code, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ },
                   uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :utm_campaign,
            uniqueness: { scope: :tenant_id, case_sensitive: false,
                          conditions: -> { where(deleted_at: nil) } }
  validates :budget_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :date_window_is_valid

  scope :attributable_on, ->(date = Date.current) {
    status_active.where("starts_on IS NULL OR starts_on <= ?", date)
                 .where("ends_on IS NULL OR ends_on >= ?", date)
  }

  def self.matching_utm(value, at: Date.current)
    normalized = value.to_s.strip.downcase
    return if normalized.blank?

    attributable_on(at).find_by(utm_campaign: normalized)
  end

  def attributable_on?(date = Date.current)
    !deleted? && status_active? && (starts_on.nil? || starts_on <= date) &&
      (ends_on.nil? || ends_on >= date)
  end

  def budget
    budget_cents / 100.0
  end

  def budget=(value)
    self.budget_cents = Cents.from(value) || 0
  end

  private

  def date_window_is_valid
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, :before_start)
  end
end
