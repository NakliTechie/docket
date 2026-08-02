class LiveChat < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  LIFETIME = 24.hours

  belongs_to :case
  belongs_to :contact

  validates :token_digest, presence: true, uniqueness: { scope: :tenant_id }
  validates :expires_at, presence: true
  validates_same_tenant :case, :contact

  scope :active, -> { where(ended_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(kase:, contact:)
    raw_token = SecureRandom.urlsafe_base64(32)
    chat = create!(case: kase, contact: contact, token_digest: digest(raw_token),
                   expires_at: LIFETIME.from_now)
    [ chat, raw_token ]
  end

  def self.authenticate(raw_token)
    return if raw_token.blank?

    active.find_by(token_digest: digest(raw_token))
  end

  def self.digest(raw_token)
    OpenSSL::Digest::SHA256.hexdigest(raw_token.to_s)
  end

  def active?
    ended_at.nil? && expires_at.future?
  end

  def keep_alive!
    update_column(:expires_at, LIFETIME.from_now)
  end

  def end!
    update!(ended_at: Time.current)
  end

  def audit_redacted_attributes
    super | %w[token_digest]
  end
end
