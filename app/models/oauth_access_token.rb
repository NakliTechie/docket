# Short-lived opaque bearer token for a service account or an OAuth user.
class OauthAccessToken < ApplicationRecord
  PREFIX = "dkts".freeze

  belongs_to :service_account, optional: true
  belongs_to :user, optional: true
  belongs_to :oauth_client, optional: true

  scope :expired, -> { where(expires_at: ...Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validate :exactly_one_principal
  validate :oauth_user_token_is_bound

  attr_reader :raw_token

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw)
  end

  def self.issue!(service_account: nil, user: nil, oauth_client: nil, scopes:, resource: nil, ttl: 1.hour)
    token = new(service_account: service_account, user: user, oauth_client: oauth_client,
                scopes: scopes, resource: resource, expires_at: ttl.from_now)
    token.send(:generate_token)
    token.save!
    token
  end

  def self.authenticate(raw)
    return nil unless raw.to_s.start_with?("#{PREFIX}_")
    token = where(revoked_at: nil).where("expires_at > ?", Time.current)
                                  .find_by(token_digest: digest(raw))
    return nil unless token&.principal&.active?
    return nil if token.user && (!token.oauth_client&.active? || token.resource != Oauth::Metadata.resource)
    token
  end

  def scope?(scope)
    scopes.include?(scope.to_s)
  end

  def principal
    service_account || user
  end

  private

  def generate_token
    @raw_token = "#{PREFIX}_#{SecureRandom.alphanumeric(40)}"
    self.token_digest = self.class.digest(@raw_token)
  end

  def exactly_one_principal
    errors.add(:base, :invalid) unless [ service_account, user ].compact.one?
  end

  def oauth_user_token_is_bound
    return unless user

    errors.add(:oauth_client, :blank) unless oauth_client
    errors.add(:resource, :blank) if resource.blank?
  end
end
