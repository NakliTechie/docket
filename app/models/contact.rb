# A customer/customer. +external_id+ is the operator's own customer
# identifier (e.g. a bank CIF) — the join key for headless integration
# and customer SSO (handoff §2).
class Contact < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include Labelable
  include HasCustomFields

  has_custom_fields_for :contacts

  LANGUAGES = %w[en hi].freeze

  belongs_to :organisation, -> { with_deleted }, optional: true
  # Which connector ingested this record (nil for portal/manual/API-created).
  belongs_to :source_connector, class_name: "Connector", optional: true
  has_many :cases, dependent: :restrict_with_error
  has_many :live_chats, dependent: :restrict_with_error
  has_many :call_records, dependent: :restrict_with_error
  has_many :deals, dependent: :nullify
  has_many :work_links, as: :linkable, dependent: :destroy
  has_many :linked_work_items, through: :work_links, source: :work_item
  has_many :messages, as: :author, dependent: nil
  has_many :crm_messages, as: :subject, dependent: :restrict_with_error
  has_many :legal_holds, as: :subject, dependent: :destroy
  has_many :privacy_erasure_requests, as: :subject, dependent: :destroy
  has_many :entitlements, dependent: nil

  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "").presence }
  normalizes :external_id, with: ->(id) { id.strip.presence }
  normalizes :job_title, with: ->(value) { value.to_s.strip.presence }
  normalizes :whatsapp_handle, with: ->(value) { value.to_s.gsub(/[^\d+]/, "").presence }
  normalizes :telegram_handle, with: ->(value) { value.to_s.strip.delete_prefix("@").presence }

  before_validation :clear_email_unsubscribed_at_on_opt_in

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :external_id, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }, allow_nil: true
  validates :preferred_language, inclusion: { in: LANGUAGES }
  validates :job_title, length: { maximum: 255 }, allow_nil: true
  validates :whatsapp_handle, format: { with: /\A\+?\d{7,15}\z/ }, allow_nil: true
  validates :telegram_handle, format: { with: /\A[a-zA-Z0-9_]{5,32}\z/ }, allow_nil: true
  validate :reachable_somehow

  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    where("LOWER(name) LIKE :t ESCAPE '\\' OR LOWER(email) LIKE :t ESCAPE '\\' OR LOWER(phone) LIKE :t ESCAPE '\\' OR LOWER(external_id) LIKE :t ESCAPE '\\'", t: term)
  }

  private

  def reachable_somehow
    return if email.present? || phone.present? || external_id.present?
    errors.add(:base, :unreachable)
  end

  def clear_email_unsubscribed_at_on_opt_in
    self.email_unsubscribed_at = nil if will_save_change_to_email_consent? && email_consent?
  end
end
