class OauthClient < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  AUTH_METHODS = %w[none client_secret_basic client_secret_post].freeze
  GRANT_TYPES = %w[authorization_code refresh_token].freeze
  RESPONSE_TYPES = %w[code].freeze
  MAX_REDIRECT_URIS = 10

  belongs_to :tenant
  has_many :authorization_codes, class_name: "OauthAuthorizationCode", dependent: :delete_all
  has_many :access_tokens, class_name: "OauthAccessToken", dependent: :delete_all
  has_many :refresh_tokens, class_name: "OauthRefreshToken", dependent: :delete_all

  validates :client_id, presence: true, uniqueness: true
  validates :client_name, presence: true, length: { maximum: 200 }
  validates :token_endpoint_auth_method, inclusion: { in: AUTH_METHODS }
  validate :redirect_uris_are_safe
  validate :grant_types_are_supported
  validate :response_types_are_supported

  attr_reader :raw_client_secret

  before_validation :generate_credentials, on: :create

  scope :active, -> { where(active: true) }

  def confidential?
    token_endpoint_auth_method != "none"
  end

  def authenticate_secret(secret)
    return secret.to_s.empty? unless confidential?
    return false if client_secret_digest.blank? || secret.blank?

    BCrypt::Password.new(client_secret_digest) == secret
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def redirect_uri_allowed?(uri)
    redirect_uris.include?(uri.to_s)
  end

  def deactivate!
    transaction do
      update!(active: false)
      authorization_codes.delete_all
      access_tokens.delete_all
      refresh_tokens.delete_all
    end
  end

  private

  def generate_credentials
    self.client_id ||= "mcp_#{SecureRandom.alphanumeric(28)}"
    return unless confidential? && client_secret_digest.blank?

    @raw_client_secret = SecureRandom.alphanumeric(48)
    self.client_secret_digest = BCrypt::Password.create(@raw_client_secret)
  end

  def redirect_uris_are_safe
    uris = Array(redirect_uris).map(&:to_s)
    if uris.empty? || uris.size > MAX_REDIRECT_URIS || uris.uniq.size != uris.size
      errors.add(:redirect_uris, :invalid)
      return
    end

    errors.add(:redirect_uris, :invalid) unless uris.all? { |uri| self.class.safe_redirect_uri?(uri) }
  end

  def grant_types_are_supported
    values = Array(grant_types).map(&:to_s)
    errors.add(:grant_types, :invalid) if values.empty? || values.include?("authorization_code") == false ||
                                         (values - GRANT_TYPES).any?
  end

  def response_types_are_supported
    values = Array(response_types).map(&:to_s)
    errors.add(:response_types, :invalid) if values != RESPONSE_TYPES
  end

  def audit_redacted_attributes
    super | %w[client_secret_digest]
  end

  class << self
    def safe_redirect_uri?(value)
      uri = URI.parse(value.to_s)
      return false unless uri.is_a?(URI::HTTP) && uri.host.present?
      return false if uri.userinfo.present? || uri.fragment.present? || uri.host.include?("*")
      return true if uri.scheme == "https"

      uri.scheme == "http" && loopback_host?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    private

    def loopback_host?(host)
      normalized = host.to_s.downcase.delete_prefix("[").delete_suffix("]")
      normalized == "localhost" || IPAddr.new(normalized).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
