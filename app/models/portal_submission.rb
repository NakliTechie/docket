# Form object for the anonymous portal: validates citizen input,
# upserts the Contact by email/phone, creates the Case and its initial
# inbound message (which carries any attachments).
class PortalSubmission
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
  attribute :phone, :string
  attribute :subject, :string
  attribute :description, :string
  attribute :preferred_language, :string, default: "en"
  attr_accessor :files

  validates :name, :subject, :description, presence: true
  validates :name, length: { maximum: 200 }, allow_blank: true
  validates :subject, length: { maximum: 300 }, allow_blank: true
  validates :description, length: { maximum: 20_000 }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 320 }, allow_blank: true
  validate :reachable_somehow
  validate :phone_plausible

  def save
    return false unless valid?

    kase = nil
    ActiveRecord::Base.transaction do
      contact = resolve_contact
      kase = Case.create!(
        subject: subject,
        contact: contact,
        channel: :web_portal,
        queue_id: Setting.get("default_queue_id")
      )
      message = kase.messages.create!(
        kind: :public_reply,
        direction: :inbound,
        author: contact,
        body: description,
        files: files.presence || []
      )
      message
    end
    kase
  rescue ActiveRecord::RecordInvalid => e
    promote_errors(e.record)
    false
  end

  private

  def normalized_email
    email.to_s.strip.downcase.presence
  end

  def normalized_phone
    phone.to_s.gsub(/[^\d+]/, "").presence
  end

  def resolve_contact
    # Anonymous submissions only dedupe onto UNVERIFIED contacts (no
    # external_id). A contact carrying a verified identity (SSO-linked via
    # external_id) must not be reachable by an email/phone match, or anyone
    # who knows a customer's email could inject a case into that customer's
    # authenticated My-Cases view (M9). Signed-in customers file via
    # Portal::MyCases#create, which attributes by session, not by email.
    unverified = Contact.where(external_id: nil)
    existing = normalized_email && unverified.find_by(email: normalized_email)
    existing ||= normalized_phone && unverified.find_by(phone: normalized_phone)
    return existing if existing

    Contact.create!(
      name: name,
      email: normalized_email,
      phone: normalized_phone,
      preferred_language: preferred_language.presence_in(Contact::LANGUAGES) || "en"
    )
  end

  def reachable_somehow
    return if normalized_email || normalized_phone
    errors.add(:base, :unreachable)
  end

  # A provided phone must look like a real number (7–15 digits, optional
  # leading +) rather than free-text garbage that would dedupe/store badly.
  def phone_plausible
    return if phone.blank?
    digits = normalized_phone.to_s.delete("+")
    errors.add(:phone, :implausible) unless digits.length.between?(7, 15)
  end

  def promote_errors(record)
    record.errors.each do |error|
      errors.add(:base, error.full_message)
    end
  end
end
