# A customer/customer. +external_id+ is the operator's own customer
# identifier (e.g. a bank CIF) — the join key for headless integration
# and customer SSO (handoff §2).
class Contact < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  LANGUAGES = %w[en hi].freeze

  belongs_to :organisation, -> { with_deleted }, optional: true
  # Which connector ingested this record (nil for portal/manual/API-created).
  belongs_to :source_connector, class_name: "Connector", optional: true
  has_many :cases, dependent: :restrict_with_error
  has_many :deals, dependent: :nullify
  has_many :work_links, as: :linkable, dependent: :destroy
  has_many :linked_work_items, through: :work_links, source: :work_item
  has_many :messages, as: :author, dependent: nil
  has_many :legal_holds, as: :subject, dependent: :destroy
  has_many :privacy_erasure_requests, as: :subject, dependent: :destroy
  has_many :entitlements, dependent: nil

  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "").presence }
  normalizes :external_id, with: ->(id) { id.strip.presence }

  before_validation :clear_email_unsubscribed_at_on_opt_in

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :external_id, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }, allow_nil: true
  validates :preferred_language, inclusion: { in: LANGUAGES }
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
