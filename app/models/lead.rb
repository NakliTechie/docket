# A sales prospect — top of the funnel (v1.2 CRM). Captured via console
# or API, worked/qualified, then CONVERTED into a Contact (+ optional
# Organisation) and, from M2, an open Deal. SoftDeletable + Audited like
# every other domain object.
class Lead < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include Labelable
  include HumanEnums

  humanizes_enums :status, :source

  enum :source, { web_form: 0, api: 1, manual: 2, import: 3, referral: 4 },
       default: :manual, prefix: true
  enum :status, { new: 0, working: 1, qualified: 2, unqualified: 3, converted: 4 },
       default: :new, prefix: true

  OPEN_STATUSES = %w[new working qualified].freeze

  belongs_to :owner, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :contact, -> { with_deleted }, optional: true
  belongs_to :converted_deal, -> { with_deleted }, class_name: "Deal", optional: true
  # Which connector ingested this record (nil for portal/manual/API-created).
  belongs_to :source_connector, class_name: "Connector", optional: true
  belongs_to :merged_into, -> { with_deleted }, class_name: "Lead", optional: true
  has_many :merged_leads, class_name: "Lead", foreign_key: :merged_into_id, dependent: nil,
                          inverse_of: :merged_into

  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "").presence }

  before_validation :clear_email_unsubscribed_at_on_opt_in

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate :reachable_somehow
  validate :merge_lineage_is_valid

  # One seam for auto-routing (PG1): console, API, and connector-created leads
  # all pass through here on create. Skipped for import-sourced leads (they
  # carry their own ownership) and any lead created with an owner already set.
  after_create :apply_lead_routing, unless: :skip_auto_routing?

  scope :open_leads, -> { where(status: OPEN_STATUSES) }
  scope :canonical, -> { where(merged_into_id: nil) }
  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    where("LOWER(name) LIKE :t ESCAPE '\\' OR LOWER(email) LIKE :t ESCAPE '\\' OR LOWER(phone) LIKE :t ESCAPE '\\' OR LOWER(company_name) LIKE :t ESCAPE '\\'", t: term)
  }

  # Convert: dedupe-or-create a Contact (same upsert rule as the portal),
  # open a Deal in the default pipeline, and stamp the lead converted.
  # Idempotent. Returns the Contact.
  def convert!
    raise ActiveRecord::RecordInvalid.new(self) if merged_into_id?
    return contact if status_converted? && contact

    transaction do
      resolved = resolve_contact
      deal = open_deal_for(resolved)
      update!(contact: resolved, converted_deal: deal, status: :converted, converted_at: Time.current)
      resolved
    end
  end

  def mark_unqualified!
    update!(status: :unqualified)
  end

  def canonical_record
    record = self
    seen = Set.new
    while record.merged_into && seen.add?(record.id)
      record = record.merged_into
    end
    record
  end

  # The UI works in whole currency units; the column stores cents.
  def value_estimate
    value_estimate_cents && value_estimate_cents / 100.0
  end

  def value_estimate=(amount)
    self.value_estimate_cents = Cents.from(amount)
  end

  private

  def skip_auto_routing?
    owner_id.present? || source_import?
  end

  def apply_lead_routing
    LeadRouting.apply(self)
  rescue StandardError => error
    # Best-effort: a routing bug must never abort lead ingestion (the hook runs
    # in the create transaction). Leave the lead unowned and log it.
    Rails.logger.error("[LeadRouting] #{error.class}: #{error.message}")
  end

  def resolve_contact
    existing = email && Contact.find_by(email: email)
    existing ||= phone && Contact.find_by(phone: phone)
    return existing if existing

    Contact.create!(name: name, email: email, phone: phone,
                    email_consent: email_consent, email_unsubscribed_at: email_unsubscribed_at,
                    organisation: resolve_organisation, preferred_language: "en")
  end

  def resolve_organisation
    return nil if company_name.blank?
    Organisation.find_or_create_by!(name: company_name) { |o| o.kind = "company" }
  end

  # Open a Deal for the converted lead in the default pipeline's first
  # stage. Nil if no pipeline is configured (convert still links a Contact).
  def open_deal_for(contact)
    pipeline = Pipeline.default
    return nil unless pipeline

    Deal.create!(
      name: company_name.presence || name,
      pipeline: pipeline, pipeline_stage: pipeline.first_stage,
      owner: owner, contact: contact, organisation: contact.organisation,
      lead: self, value_cents: value_estimate_cents
    )
  end

  def reachable_somehow
    return if email.present? || phone.present?
    errors.add(:base, :unreachable)
  end

  def clear_email_unsubscribed_at_on_opt_in
    self.email_unsubscribed_at = nil if will_save_change_to_email_consent? && email_consent?
  end

  def merge_lineage_is_valid
    return if merged_into.nil?

    errors.add(:merged_into, :cannot_be_self) if merged_into.equal?(self) || merged_into_id == id
    errors.add(:merged_into, :already_merged) if merged_into.merged_into_id?
    errors.add(:merged_into, :cross_tenant) if merged_into.tenant_id != tenant_id
  end
end
