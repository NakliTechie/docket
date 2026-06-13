# A citizen/customer. +external_id+ is the operator's own customer
# identifier (e.g. a bank CIF) — the join key for headless integration
# and customer SSO (handoff §2).
class Contact < ApplicationRecord
  include SoftDeletable
  include Audited

  LANGUAGES = %w[en hi].freeze

  belongs_to :organisation, -> { with_deleted }, optional: true
  # Which connector ingested this record (nil for portal/manual/API-created).
  belongs_to :source_connector, class_name: "Connector", optional: true
  has_many :cases, dependent: :restrict_with_error
  has_many :messages, as: :author, dependent: nil

  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "").presence }
  normalizes :external_id, with: ->(id) { id.strip.presence }

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :external_id, uniqueness: { conditions: -> { where(deleted_at: nil) } }, allow_nil: true
  validates :preferred_language, inclusion: { in: LANGUAGES }
  validate :reachable_somehow

  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    where("LOWER(name) LIKE :t OR LOWER(email) LIKE :t OR LOWER(phone) LIKE :t OR LOWER(external_id) LIKE :t", t: term)
  }

  private

  def reachable_somehow
    return if email.present? || phone.present? || external_id.present?
    errors.add(:base, :unreachable)
  end
end
