# Permission vocabulary + role→permission matrix: the single source of truth
# for "what may each role do". Policies ask `user.can?("resource:action")`
# instead of hard-coding role names, so adding a role is one row here, not a
# branch across every policy. See plan/rbac-research-2026-06-13.md.
#
# Pure constant — no tables. Promote to DB-backed roles only when an operator
# must define custom roles at runtime; `User#can?` is the seam that keeps that
# change localized.
#
# Transition invariant: the LEGACY sets (admin/supervisor/agent) reproduce each
# role's authority under the OLD policies EXACTLY, so deploying the matrix
# changes no existing user's authority. The functional roles carry the target
# design; authority only changes when an admin deliberately reassigns a user.
module Authz
  # The closed permission vocabulary. `resource:action`. Every value used in any
  # role set below must be a member (asserted in test). Granularity is chosen to
  # preserve every distinction the current policies make — e.g. case_config:manage
  # (queues/categories/SLAs/macros) is separate from case:write because an agent
  # may edit cases but not the case-desk configuration.
  PERMISSIONS = %w[
    case:read case:write case:delete case_config:manage ai:autonomy
    contact:read contact:write contact:delete
    lead:read lead:write lead:delete
    deal:read deal:write deal:delete
    pipeline:read pipeline:manage sequence:enroll
    report:operational report:sales finance:read finance:write
    connector:read connector:operate connector:manage connector:invoke
    invocation:review reference_doc:manage
    user:manage settings:manage audit:read tenant:manage
    service_account:manage api_token:manage webhook:manage
  ].freeze

  # ── Functional roles (the target model) ────────────────────────────────────
  # super_admin holds everything; the rest are least-privilege slices. Two
  # deliberate separation-of-duties choices: platform plumbing (settings:manage,
  # connector:manage, service_account:manage, ai:autonomy) is super_admin-only,
  # and invocation:review (the human-of-record approval) never sits with a
  # purely-operational role (maker-checker).
  #
  # Tenancy: super_admin is the cross-tenant/platform tier, client_admin the
  # per-tenant org admin — that distinction is enforced in the SCOPING layer
  # (without_tenant), not here; this matrix is tenant-agnostic.
  FUNCTIONAL = {
    "super_admin" => PERMISSIONS,
    "client_admin" => %w[
      case:read case:write case:delete case_config:manage
      contact:read contact:write contact:delete
      lead:read lead:write lead:delete deal:read deal:write deal:delete
      pipeline:read pipeline:manage sequence:enroll
      report:operational report:sales finance:read finance:write
      invocation:review reference_doc:manage connector:invoke
      user:manage audit:read
    ].freeze,
    "finance" => %w[
      case:read contact:read lead:read deal:read pipeline:read
      report:operational report:sales finance:read finance:write
    ].freeze,
    "sales" => %w[
      case:read contact:read contact:write
      lead:read lead:write deal:read deal:write pipeline:read
      sequence:enroll report:sales
    ].freeze,
    "customer_service" => %w[
      case:read case:write contact:read contact:write
      report:operational connector:invoke
    ].freeze,
    "technical" => %w[
      case:read contact:read report:operational
      connector:read connector:operate reference_doc:manage webhook:manage
    ].freeze,
    "readonly" => %w[
      case:read contact:read lead:read deal:read pipeline:read report:sales
    ].freeze
  }.freeze

  # The legacy admin/supervisor/agent roles + their transitional aliases were
  # retired by the MigrateLegacyRoles cutover — ROLE_PERMISSIONS is now the
  # functional matrix alone.
  ROLE_PERMISSIONS = FUNCTIONAL

  # Functional roles surfaced as assignment targets + in the admin matrix page.
  ASSIGNABLE_ROLES = FUNCTIONAL.keys.freeze

  module_function

  def permissions_for(role)
    ROLE_PERMISSIONS.fetch(role.to_s, [])
  end
end
