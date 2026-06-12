# A configured integration. The provider (registry key) decides HOW to
# fetch; the connector holds the WHAT — endpoint config, encrypted
# credentials, the field mapping into a Docket entity, and the schedule.
class Connector < ApplicationRecord
  include SoftDeletable
  include Audited

  # Credential vault: secrets (api keys, tokens) encrypted at rest.
  encrypts :credentials

  TARGETS = %w[contacts].freeze

  has_many :connector_runs, dependent: :delete_all
  has_many :invocations, class_name: "ConnectorInvocation", dependent: :destroy

  enum :status, { active: 0, paused: 1, error: 2 }, prefix: true

  validates :name, presence: true
  validates :target, inclusion: { in: TARGETS }
  validate :provider_is_known
  validate :mapping_reaches_a_contact

  before_validation :ensure_webhook_secret, on: :create

  scope :active, -> { where(status: :active) }

  def provider_instance
    Connectors::Registry.build(provider, self)
  end

  def provider_descriptor
    Connectors::Registry.descriptor(provider)
  end

  # The agent-callable actions this provider declares, and a key lookup.
  def provider_actions
    Connectors::Registry.klass(provider)&.actions || []
  end

  def provider_action(key)
    Connectors::Registry.klass(provider)&.action(key)
  end

  # Effector authorization: which actions are exposed to agents (deny by
  # default) and which writes skip the human-of-record gate.
  def enabled_actions = super || []
  def auto_approve_actions = super || []
  def enabled_action?(key) = enabled_actions.map(&:to_s).include?(key.to_s)
  def auto_approves?(key) = auto_approve_actions.map(&:to_s).include?(key.to_s)

  # Parsed secret blob; never logged or audited (see redaction below).
  def credentials_hash
    JSON.parse(credentials.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def credentials_hash=(hash)
    self.credentials = JSON.generate(hash.to_h.reject { |_, v| v.to_s.strip.empty? })
  end

  def config_value(key)
    (config || {})[key.to_s]
  end

  def due?(now = Time.current)
    return false unless status_active? && schedule_interval_minutes.present?
    last_synced_at.nil? || last_synced_at <= now - schedule_interval_minutes.minutes
  end

  def audit_redacted_attributes
    super | %w[credentials webhook_secret]
  end

  private

  def ensure_webhook_secret
    self.webhook_secret ||= "whk_#{SecureRandom.alphanumeric(40)}"
  end

  def provider_is_known
    errors.add(:provider, :unknown) unless Connectors::Registry.key?(provider)
  end

  # A pull is useless if nothing maps to an identity we can upsert on.
  def mapping_reaches_a_contact
    return unless target == "contacts"
    mapped = (field_mapping || {}).keys.map(&:to_s)
    return if (mapped & %w[external_id email]).any?
    errors.add(:field_mapping, :needs_identity)
  end
end
