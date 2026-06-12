# A configured integration. The provider (registry key) decides HOW to
# fetch; the connector holds the WHAT — endpoint config, encrypted
# credentials, the field mapping into a Docket entity, and the schedule.
class Connector < ApplicationRecord
  include SoftDeletable
  include Audited

  # Credential vault: secrets (api keys, tokens) encrypted at rest.
  encrypts :credentials

  TARGETS = %w[contacts].freeze

  belongs_to :shared_credential, optional: true
  has_many :connector_runs, dependent: :delete_all
  has_many :invocations, class_name: "ConnectorInvocation", dependent: :destroy

  # draft = wired but not live (configure-later): excluded from the active
  # scope, so agents and the scheduler never touch it until it's activated.
  enum :status, { active: 0, paused: 1, error: 2, draft: 3 }, prefix: true

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

  # Effector-only providers (notify / pay) don't pull records inbound.
  def provider_syncs?
    provider_descriptor.nil? || provider_descriptor.syncs?
  end

  # Has every required secret (own vault or shared)? A draft connector can be
  # activated once this is true — "wire now, configure (and go live) later".
  def configured?
    return true unless provider_descriptor
    provider_descriptor.required_secret_fields.all? { |field| secret(field).present? }
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

  # Resolve a secret field: this connector's own vault first, then the shared
  # app-level credential it references (a licence/key reused across connectors).
  def secret(field)
    key = field.to_s
    own = credentials_hash[key]
    return own if own.present?
    shared_credential&.secret(key)
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

  # A pull is useless if nothing maps to an identity we can upsert on — but
  # effector-only providers (notify / pay) don't sync, so they need no mapping.
  def mapping_reaches_a_contact
    return unless provider_syncs? && target == "contacts"
    mapped = (field_mapping || {}).keys.map(&:to_s)
    return if (mapped & %w[external_id email]).any?
    errors.add(:field_mapping, :needs_identity)
  end
end
