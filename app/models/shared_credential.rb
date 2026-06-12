# An app-level secret/licence reused across connectors — one API Setu key, a
# UIDAI licence, a shared Razorpay account. Holds a named bag of secrets
# (encrypted at rest, redacted from the audit log). A connector references one
# and its provider reads through Connector#secret (own vault first, then here).
class SharedCredential < ApplicationRecord
  include SoftDeletable
  include Audited

  encrypts :secrets

  # The secret fields the admin form offers (the union the providers read).
  COMMON_FIELDS = %w[api_key api_secret authkey key_id key_secret webhook_url license_id token].freeze

  has_many :connectors, dependent: :nullify

  normalizes :name, with: ->(n) { n.to_s.strip.downcase }

  validates :name, presence: true,
            uniqueness: { conditions: -> { where(deleted_at: nil) } },
            format: { with: /\A[a-z0-9_]+\z/ }
  validates :label, presence: true

  scope :ordered, -> { order(:label) }

  # Parsed secret bag; never logged or audited (redaction below).
  def secrets_hash
    JSON.parse(secrets.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def secrets_hash=(hash)
    self.secrets = JSON.generate(hash.to_h.reject { |_, v| v.to_s.strip.empty? })
  end

  def secret(field)
    secrets_hash[field.to_s].presence
  end

  def audit_redacted_attributes
    super | %w[secrets]
  end
end
