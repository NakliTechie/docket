# Machine-to-machine identity (handoff §5): OAuth2 client-credentials
# with scopes. This is how the operator's own systems (netbanking,
# branch CRM, IVR backend) call Docket headlessly.
class ServiceAccount < ApplicationRecord
  include SoftDeletable
  include Audited

  SCOPES = %w[
    cases:read cases:write
    contacts:read contacts:write
    organisations:read organisations:write
    config:read config:write
    audit:read
    webhooks:manage
  ].freeze

  has_many :oauth_access_tokens, dependent: :delete_all

  validates :name, presence: true
  validates :client_id, presence: true, uniqueness: true
  validates :scopes, presence: true
  validate :scopes_are_known

  attr_reader :raw_client_secret

  before_validation :generate_credentials, on: :create
  # Reducing (or otherwise changing) scopes must not leave already-issued
  # 1h access tokens carrying the old, broader scopes — revoke them so the
  # integration re-issues at the new scope set.
  after_update :revoke_tokens_on_scope_change

  scope :active, -> { where(active: true) }

  def self.authenticate(client_id, client_secret)
    account = active.find_by(client_id: client_id)
    return nil unless account
    BCrypt::Password.new(account.client_secret_digest) == client_secret ? account : nil
  rescue BCrypt::Errors::InvalidHash
    nil
  end

  def issue_access_token!(ttl: 1.hour)
    OauthAccessToken.issue!(service_account: self, scopes: scopes, ttl: ttl)
  end

  def rotate_secret!
    @raw_client_secret = SecureRandom.alphanumeric(48)
    update!(client_secret_digest: BCrypt::Password.create(@raw_client_secret))
    oauth_access_tokens.delete_all
    @raw_client_secret
  end

  def scope?(scope)
    scopes.include?(scope.to_s)
  end

  def deactivate!
    transaction do
      update!(active: false)
      oauth_access_tokens.delete_all
    end
  end

  private

  def generate_credentials
    self.client_id ||= "svc_#{SecureRandom.alphanumeric(20)}"
    if client_secret_digest.blank?
      @raw_client_secret = SecureRandom.alphanumeric(48)
      self.client_secret_digest = BCrypt::Password.create(@raw_client_secret)
    end
  end

  def scopes_are_known
    unknown = Array(scopes) - SCOPES
    errors.add(:scopes, :invalid) if unknown.any? || Array(scopes).empty?
  end

  def revoke_tokens_on_scope_change
    oauth_access_tokens.delete_all if saved_change_to_scopes?
  end

  def audit_redacted_attributes
    super | %w[client_secret_digest]
  end
end
