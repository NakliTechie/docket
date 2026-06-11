# Form object for the public lead-capture form (v1.2 CRM). Unauthenticated
# surface — validates and length-caps input, then creates a web_form Lead.
# Honeypot handling lives in the controller (silent, so bots get no signal).
class LeadInquiry
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
  attribute :phone, :string
  attribute :company_name, :string
  attribute :message, :string

  validates :name, presence: true, length: { maximum: 200 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true, length: { maximum: 255 }
  validates :phone, length: { maximum: 50 }
  validates :company_name, length: { maximum: 200 }
  validates :message, length: { maximum: 5_000 }
  validate :reachable_somehow

  def save
    return false unless valid?

    Lead.create!(
      name: name, email: email.presence, phone: phone.presence,
      company_name: company_name.presence, notes: message.presence,
      source: :web_form, status: :new
    )
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |err| errors.add(:base, err.full_message) }
    false
  end

  private

  def reachable_somehow
    errors.add(:base, :unreachable) if email.blank? && phone.blank?
  end
end
