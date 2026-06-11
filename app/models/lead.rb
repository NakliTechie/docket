# A sales prospect — top of the funnel (v1.2 CRM). Captured via console
# or API, worked/qualified, then CONVERTED into a Contact (+ optional
# Organisation) and, from M2, an open Deal. SoftDeletable + Audited like
# every other domain object.
class Lead < ApplicationRecord
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :status, :source

  enum :source, { web_form: 0, api: 1, manual: 2, import: 3, referral: 4 },
       default: :manual, prefix: true
  enum :status, { new: 0, working: 1, qualified: 2, unqualified: 3, converted: 4 },
       default: :new, prefix: true

  OPEN_STATUSES = %w[new working qualified].freeze

  belongs_to :owner, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :contact, -> { with_deleted }, optional: true

  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "").presence }

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate :reachable_somehow

  scope :open_leads, -> { where(status: OPEN_STATUSES) }
  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    where("LOWER(name) LIKE :t OR LOWER(email) LIKE :t OR LOWER(phone) LIKE :t OR LOWER(company_name) LIKE :t", t: term)
  }

  # Convert: dedupe-or-create a Contact (same upsert rule as the portal),
  # link it, and stamp the lead converted. Idempotent. M2 will also open a
  # Deal here. Returns the Contact.
  def convert!
    return contact if status_converted? && contact

    transaction do
      resolved = resolve_contact
      update!(contact: resolved, status: :converted, converted_at: Time.current)
      resolved
    end
  end

  def mark_unqualified!
    update!(status: :unqualified)
  end

  # The UI works in whole currency units; the column stores cents.
  def value_estimate
    value_estimate_cents && value_estimate_cents / 100.0
  end

  def value_estimate=(amount)
    self.value_estimate_cents = amount.present? ? (amount.to_f * 100).round : nil
  end

  private

  def resolve_contact
    existing = email && Contact.find_by(email: email)
    existing ||= phone && Contact.find_by(phone: phone)
    return existing if existing

    Contact.create!(name: name, email: email, phone: phone,
                    organisation: resolve_organisation, preferred_language: "en")
  end

  def resolve_organisation
    return nil if company_name.blank?
    Organisation.find_or_create_by!(name: company_name) { |o| o.kind = "company" }
  end

  def reachable_somehow
    return if email.present? || phone.present?
    errors.add(:base, :unreachable)
  end
end
