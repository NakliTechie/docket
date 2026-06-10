# Per-user API token (handoff §5): revocable, admin-issued, full parity
# with the user's console permissions (Pundit policies apply). The raw
# token is shown exactly once at creation; only a SHA-256 digest is
# stored.
class ApiToken < ApplicationRecord
  include Audited

  PREFIX = "dkt".freeze

  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  attr_reader :raw_token

  scope :usable, -> { where(revoked_at: nil) }

  before_validation :generate_token, on: :create

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw)
  end

  def self.authenticate(raw)
    return nil unless raw.to_s.start_with?("#{PREFIX}_")
    token = usable.find_by(token_digest: digest(raw))
    return nil unless token&.user&.active?
    token.update_columns(last_used_at: Time.current)
    token
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  private

  def generate_token
    return if token_digest.present?
    @raw_token = "#{PREFIX}_#{SecureRandom.alphanumeric(40)}"
    self.token_digest = self.class.digest(@raw_token)
  end

  def audit_redacted_attributes
    super | %w[token_digest]
  end
end
