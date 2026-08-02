class LiveChatSubmission
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
  attribute :phone, :string
  attribute :message, :string
  attribute :preferred_language, :string, default: "en"
  attr_accessor :contact

  validates :message, presence: true, length: { maximum: 20_000 }
  validates :name, presence: true, length: { maximum: 200 }, unless: :signed_in?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 320 }, allow_blank: true
  validate :reachable_somehow, unless: :signed_in?
  validate :phone_plausible

  def save
    return false unless valid?

    result = nil
    ActiveRecord::Base.transaction do
      customer = contact || resolve_contact
      kase = Case.create!(
        subject: message.to_s.squish.truncate(120), contact: customer,
        channel: :live_chat, queue_id: Setting.get("default_queue_id")
      )
      live_chat, raw_token = LiveChat.issue!(kase: kase, contact: customer)
      Current.set(actor: customer) do
        kase.messages.create!(kind: :public_reply, direction: :inbound,
                              author: customer, body: message)
      end
      result = [ live_chat, raw_token ]
    end
    result
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.each { |record_error| errors.add(:base, record_error.full_message) }
    false
  end

  private

  def signed_in?
    contact.present?
  end

  def normalized_email
    email.to_s.strip.downcase.presence
  end

  def normalized_phone
    phone.to_s.gsub(/[^\d+]/, "").presence
  end

  def resolve_contact
    unverified = Contact.where(external_id: nil)
    existing = normalized_email && unverified.find_by(email: normalized_email)
    existing ||= normalized_phone && unverified.find_by(phone: normalized_phone)
    existing || Contact.create!(
      name: name, email: normalized_email, phone: normalized_phone,
      preferred_language: preferred_language.presence_in(Contact::LANGUAGES) || "en"
    )
  end

  def reachable_somehow
    errors.add(:base, :unreachable) unless normalized_email || normalized_phone
  end

  def phone_plausible
    return if phone.blank?

    digits = normalized_phone.to_s.delete("+")
    errors.add(:phone, :implausible) unless digits.length.between?(7, 15)
  end
end
