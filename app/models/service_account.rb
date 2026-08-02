# Machine-to-machine identity (handoff §5): OAuth2 client-credentials
# with scopes. This is how the operator's own systems (netbanking,
# branch CRM, IVR backend) call Docket headlessly.
class ServiceAccount < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  SCOPES = %w[
    cases:read cases:write
    contacts:read contacts:write
    organisations:read organisations:write
    crm:read crm:write
    work:read work:write work:manage
    config:read config:write
    audit:read
    webhooks:manage
    connectors:read connectors:invoke
  ].freeze

  # Each M2M scope projected onto the console permission vocabulary, so a scope
  # is a provable slice of Authz::PERMISSIONS rather than a parallel hand-list.
  # A test asserts the values are a subset of Authz::PERMISSIONS and the keys
  # match SCOPES exactly (catches drift either way). See plan/rbac-research.
  SCOPE_PERMISSIONS = {
    "cases:read" => %w[case:read],
    "cases:write" => %w[case:write],
    "contacts:read" => %w[contact:read],
    "contacts:write" => %w[contact:write],
    "organisations:read" => %w[contact:read],
    "organisations:write" => %w[contact:write],
    "crm:read" => %w[lead:read deal:read pipeline:read activity:read],
    "crm:write" => %w[lead:write deal:write activity:write],
    "work:read" => %w[work:read],
    "work:write" => %w[work:write],
    # Configuring a workspace is a tier above doing the work in it, exactly as
    # config:write sits above cases:write. Without this, endpoints whose policy
    # demands project:manage had NO scope that could express it.
    "work:manage" => %w[project:manage],
    "config:read" => %w[settings:manage knowledge:read],
    "config:write" => %w[settings:manage queue:manage routing:manage sla:manage macro:manage
                          crm_config:manage knowledge:draft knowledge:review knowledge:publish knowledge:admin],
    "audit:read" => %w[audit:read],
    "webhooks:manage" => %w[webhook:manage],
    "connectors:read" => %w[connector:read],
    "connectors:invoke" => %w[connector:invoke]
  }.freeze

  has_many :oauth_access_tokens, dependent: :delete_all
  has_many :connector_grants, class_name: "ServiceAccountConnectorGrant", dependent: :destroy

  # Default rolling window for the effector action budget when an agent sets
  # a budget but no window (see Connectors::Budget).
  DEFAULT_BUDGET_WINDOW_MINUTES = 60

  validates :name, presence: true
  # DELIBERATELY not scoped to live rows: reissuing a deleted account's
  # client_id would let a credential someone still holds resolve to a different
  # principal. An identifier that was ever issued is never reused.
  validates :client_id, presence: true, uniqueness: true
  validates :scopes, presence: true
  validate :scopes_are_known
  validate :connector_grant_selection_is_valid, if: :connector_grant_selection_assigned?
  validates :action_budget, numericality: { greater_than: 0 }, allow_nil: true
  validates :action_budget_window_minutes, numericality: { greater_than: 0 }, allow_nil: true

  attr_reader :raw_client_secret

  before_validation :generate_credentials, on: :create
  # Reducing (or otherwise changing) scopes must not leave already-issued
  # 1h access tokens carrying the old, broader scopes — revoke them so the
  # integration re-issues at the new scope set.
  after_update :revoke_tokens_on_scope_change
  after_save :persist_connector_grant_selection, if: :connector_grant_selection_assigned?
  after_update :revoke_connector_grants_without_scope, if: :saved_change_to_scopes?

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

  def connector_action_granted?(connector, action)
    return false unless scope?("connectors:invoke")

    connector_grants.find_by(connector_id: connector.id)&.grants?(action) || false
  end

  def grant_connector_actions!(connector, actions = connector.enabled_actions)
    grant = connector_grants.find_or_initialize_by(connector: connector)
    grant.tenant = tenant
    grant.actions = actions
    grant.save!
    grant
  end

  def connector_grant_selection
    return @connector_grant_selection if connector_grant_selection_assigned?

    connector_grants.each_with_object({}) do |grant, selection|
      selection[grant.connector_id.to_s] = grant.actions
    end
  end

  def connector_grant_selection=(raw_selection)
    @connector_grant_selection_assigned = true
    @connector_grant_selection = raw_selection.to_h.each_with_object({}) do |(connector_id, actions), selection|
      selected = Array(actions).map(&:to_s).reject(&:blank?).uniq
      selection[connector_id.to_s] = selected if selected.any?
    end
  end

  # Effector budgeted autonomy: nil budget = unlimited.
  def effector_budgeted?
    action_budget.present?
  end

  def effector_budget_window_minutes
    action_budget_window_minutes || DEFAULT_BUDGET_WINDOW_MINUTES
  end

  def deactivate!
    transaction do
      update!(active: false)
      oauth_access_tokens.delete_all
    end
  end

  private

  def connector_grant_selection_assigned?
    @connector_grant_selection_assigned == true
  end

  def persist_connector_grant_selection
    desired = scope?("connectors:invoke") ? @connector_grant_selection : {}
    connectors = Connector.where(id: desired.keys).index_by { |connector| connector.id.to_s }

    retained_ids = connectors.values.map(&:id)
    retained_ids.any? ? connector_grants.where.not(connector_id: retained_ids).destroy_all : connector_grants.destroy_all
    desired.each do |connector_id, actions|
      connector = connectors.fetch(connector_id)
      grant = connector_grants.find_or_initialize_by(connector: connector)
      grant.tenant = tenant
      grant.actions = actions
      grant.save!
    end
  end

  def revoke_connector_grants_without_scope
    connector_grants.destroy_all unless scope?("connectors:invoke")
  end

  def connector_grant_selection_is_valid
    return unless scope?("connectors:invoke")

    connectors = Connector.where(id: @connector_grant_selection.keys).index_by { |connector| connector.id.to_s }
    unknown_ids = @connector_grant_selection.keys - connectors.keys
    errors.add(:connector_grant_selection, :invalid_connector) if unknown_ids.any?

    @connector_grant_selection.each do |connector_id, actions|
      connector = connectors[connector_id]
      next unless connector

      unknown_actions = actions - connector.enabled_actions.map(&:to_s)
      if unknown_actions.any?
        errors.add(:connector_grant_selection, :invalid_actions,
                   connector: connector.name, actions: unknown_actions.join(", "))
      end
    end
  end

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
