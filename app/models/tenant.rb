# The apex of the tenancy seam (see db/migrate/.../create_tenants). One row =
# one organisation. NOT itself tenant-scoped (no acts_as_tenant) and NOT
# soft-deletable — it sits above the data it owns. Audited so tenant
# provisioning/suspension lands in the hash chain.
class Tenant < ApplicationRecord
  include Audited

  # The isolated-deploy singleton's slug.
  PRIMARY_SLUG = "primary".freeze

  enum :status, { active: 0, suspended: 1 }, default: :active

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  # Subdomain is NULL for the isolated singleton; unique + DNS-label-shaped when set.
  validates :subdomain, uniqueness: true, allow_blank: true,
            format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }, allow_nil: true

  # Deployment topology (set from DOCKET_DEPLOYMENT_MODE in the tenancy
  # initializer). isolated = one DB per client (default, the procurement asset);
  # shared = many tenants on shared infra, resolved by subdomain.
  def self.deployment_mode
    Rails.application.config.x.tenancy_mode
  end

  def self.shared_deployment?
    deployment_mode == "shared"
  end

  def self.isolated_deployment?
    !shared_deployment?
  end

  # The isolated-deploy singleton. In a SHARED deploy there is no "primary" —
  # request resolution comes from the subdomain instead (guarded by mode), so
  # callers must only reach for this on the isolated path.
  def self.primary
    find_by(slug: PRIMARY_SLUG) || order(:id).first
  end

  # The single source of truth for host→tenant resolution, shared by the
  # request before_action (TenantResolution) and the CORS middleware (which
  # runs before it and must read per-tenant settings — M1). isolated → the
  # singleton; shared → the active tenant for the subdomain, or nil (unknown).
  def self.resolve_by_subdomain(subdomain)
    shared_deployment? ? active.find_by(subdomain: subdomain.presence) : primary
  end

  def display_label
    name
  end
end
