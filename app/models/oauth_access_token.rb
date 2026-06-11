# Short-lived opaque bearer token from the client-credentials grant.
class OauthAccessToken < ApplicationRecord
  PREFIX = "dkts".freeze

  belongs_to :service_account

  scope :expired, -> { where(expires_at: ...Time.current) }

  validates :token_digest, presence: true, uniqueness: true

  attr_reader :raw_token

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw)
  end

  def self.issue!(service_account:, scopes:, ttl: 1.hour)
    token = new(service_account: service_account, scopes: scopes, expires_at: ttl.from_now)
    token.send(:generate_token)
    token.save!
    token
  end

  def self.authenticate(raw)
    return nil unless raw.to_s.start_with?("#{PREFIX}_")
    token = where(revoked_at: nil).where("expires_at > ?", Time.current)
                                  .find_by(token_digest: digest(raw))
    return nil unless token&.service_account&.active?
    token
  end

  def scope?(scope)
    scopes.include?(scope.to_s)
  end

  private

  def generate_token
    @raw_token = "#{PREFIX}_#{SecureRandom.alphanumeric(40)}"
    self.token_digest = self.class.digest(@raw_token)
  end
end
