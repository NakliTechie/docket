class ServiceAccountConnectorGrant < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :service_account
  belongs_to :connector

  validates :service_account_id, uniqueness: { scope: %i[tenant_id connector_id] }
  validate :actions_are_enabled
  validate :service_account_may_invoke

  before_validation :normalize_actions

  scope :ordered, -> { includes(:connector).joins(:connector).order("connectors.name", :id) }

  def grants?(action)
    actions.include?(action.to_s)
  end

  private

  def normalize_actions
    self.actions = Array(actions).map(&:to_s).reject(&:blank?).uniq.sort
  end

  def actions_are_enabled
    return unless connector

    unknown = actions - connector.enabled_actions.map(&:to_s)
    errors.add(:actions, :invalid, actions: unknown.join(", ")) if unknown.any?
    errors.add(:actions, :blank) if actions.empty?
  end

  def service_account_may_invoke
    return if service_account&.scope?("connectors:invoke")

    errors.add(:service_account, :missing_connector_scope)
  end
end
