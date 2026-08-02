class OauthRefreshToken < ApplicationRecord
  PREFIX = "dktr".freeze
  TTL = 30.days

  acts_as_tenant(:tenant)

  belongs_to :tenant
  belongs_to :oauth_client
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :scopes, :resource, presence: true

  attr_reader :raw_token

  scope :expired, -> { where(expires_at: ...Time.current) }

  before_validation :generate_token, on: :create

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def self.issue!(oauth_client:, user:, scopes:, resource:)
    create!(tenant: user.tenant, oauth_client: oauth_client, user: user,
            scopes: scopes, resource: resource, expires_at: TTL.from_now)
  end

  def usable?
    revoked_at.nil? && expires_at.future? && oauth_client.active? && user.active?
  end

  private

  def generate_token
    @raw_token = "#{PREFIX}_#{SecureRandom.urlsafe_base64(48, false)}"
    self.token_digest = self.class.digest(@raw_token)
  end
end
