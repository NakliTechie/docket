# The entitlement vocabulary: what may be turned on or off for a tenant.
#
# Docket ships in two SKUs off ONE codebase — shared SaaS (many tenants,
# subdomain-resolved) and a dedicated server (the isolated singleton). Both use
# this registry; only where the toggles are *set* differs (platform console vs
# the operator on the primary tenant). See plan/one-docket-workplan.md Batch ENT.
#
# Pure constant, no tables — the same choice Authz makes, for the same reason:
# an entitlement is a deploy-time product decision, not runtime data. Promote to
# DB-backed rows only when a plan/billing engine needs to define them at runtime;
# `Tenant#feature?` is the seam that keeps that change localized.
#
# Invariant that protects existing deploys: every key here defaults to ENABLED,
# and a tenant stores only explicit overrides. So an untouched isolated deploy
# behaves exactly as it did before entitlements existed — asserted in test by the
# pre-existing suite passing unchanged.
module Features
  # A feature is `module` or `module.feature`. The dot is the dependency: a
  # sub-feature is dead whenever its module is off, without restating it here.
  MODULES = %w[service_desk crm work].freeze

  # key => permissions the feature owns. A permission listed here is revoked by
  # `User#can?` when the feature is off (Authz says what a ROLE may do;
  # entitlements say what the TENANT bought — a permission needs both).
  #
  # Permissions deliberately left unmapped are deploy-wide plumbing that no
  # module owns: user:manage, settings:manage, audit:read, tenant:manage,
  # service_account:manage, api_token:manage, webhook:manage, and the
  # contact:*/report:operational/finance:* set shared by every module.
  REGISTRY = {
    "service_desk" => %w[case:read case:write case:delete case_config:manage],
    "service_desk.kb" => %w[reference_doc:manage],
    "service_desk.approvals" => %w[invocation:review],
    "service_desk.portal" => [],

    "crm" => %w[lead:read lead:write lead:delete deal:read deal:write deal:delete
                pipeline:read pipeline:manage report:sales],
    "crm.sequences" => %w[sequence:enroll],

    "work" => %w[work:read work:write project:manage],
    "work.sprints" => [],

    "decisioning" => %w[ai:autonomy],
    "connectors" => %w[connector:read connector:operate connector:manage connector:invoke],
    "mcp" => []
  }.freeze

  KEYS = REGISTRY.keys.freeze

  # permission => the one feature that owns it (built once; asserted unique).
  PERMISSION_OWNER = REGISTRY.each_with_object({}) do |(key, permissions), map|
    permissions.each { |permission| map[permission] = key }
  end.freeze

  module_function

  # The ambient answer: is this feature on for the tenant in scope? Used by the
  # controller guard, the nav, and `User#can?`. With NO tenant resolved (the
  # platform console's without_tenant, a rake task) entitlements don't apply and
  # this is permissive — the platform tier sits above per-tenant packaging.
  def enabled?(key)
    tenant = ActsAsTenant.current_tenant
    return exists?(key) if tenant.nil?

    tenant.feature?(key)
  end

  def exists?(key)
    KEYS.include?(key.to_s)
  end

  # "crm.sequences" => ["crm", "crm.sequences"] — the chain that must ALL be on.
  # An unknown key yields an empty chain; callers treat that as fail-closed.
  def chain(key)
    key = key.to_s
    return [] unless exists?(key)

    module_key, sub = key.split(".", 2)
    sub ? [ module_key, key ] : [ key ]
  end

  def owner_of(permission)
    PERMISSION_OWNER[permission.to_s]
  end

  # Grouped for the console: module key => its sub-feature keys.
  def grouped
    KEYS.each_with_object({}) do |key, groups|
      module_key, sub = key.split(".", 2)
      groups[module_key] ||= []
      groups[module_key] << key if sub
    end
  end

  # Named entitlement sets for provisioning. `full` is the default and the
  # Netcore shape (all three pillars). A preset lists only what it DISABLES,
  # because enabled-by-default is the invariant above.
  PRESETS = {
    "full" => [],
    "service_only" => %w[crm crm.sequences work work.sprints],
    "crm_only" => %w[service_desk service_desk.kb service_desk.approvals
                     service_desk.portal work work.sprints],
    "work_only" => %w[service_desk service_desk.kb service_desk.approvals
                      service_desk.portal crm crm.sequences]
  }.freeze

  def preset(name)
    disabled = PRESETS.fetch(name.to_s) { raise ArgumentError, "unknown preset #{name}" }
    disabled.index_with { false }
  end
end
