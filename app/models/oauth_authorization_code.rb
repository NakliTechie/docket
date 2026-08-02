class OauthAuthorizationCode < ApplicationRecord
  PREFIX = "dkoac".freeze
  TTL = 5.minutes
  VERIFIER_PATTERN = /\A[A-Za-z0-9._~-]{43,128}\z/

  acts_as_tenant(:tenant)

  belongs_to :tenant
  belongs_to :oauth_client
  belongs_to :user

  validates :code_digest, presence: true, uniqueness: true
  validates :redirect_uri, :code_challenge, :resource, presence: true
  validates :scopes, presence: true

  attr_reader :raw_code

  scope :expired, -> { where(expires_at: ...Time.current) }

  before_validation :generate_code, on: :create

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def self.issue!(oauth_client:, user:, redirect_uri:, code_challenge:, scopes:, resource:)
    create!(tenant: user.tenant, oauth_client: oauth_client, user: user,
            redirect_uri: redirect_uri, code_challenge: code_challenge,
            scopes: scopes, resource: resource, expires_at: TTL.from_now)
  end

  def usable?
    consumed_at.nil? && expires_at.future? && oauth_client.active? && user.active?
  end

  def pkce_matches?(verifier)
    return false unless verifier.to_s.match?(VERIFIER_PATTERN)

    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(code_challenge, expected)
  end

  private

  def generate_code
    @raw_code = "#{PREFIX}_#{SecureRandom.urlsafe_base64(36, false)}"
    self.code_digest = self.class.digest(@raw_code)
  end
end
