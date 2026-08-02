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
  # preserve every distinction the policies make. Configuration permissions
  # remain separate from operational writes, and lifecycle permissions separate
  # drafting, review, publication, and administration.
  PERMISSIONS = %w[
    case:read case:write case:delete case:collaborate ai:autonomy
    queue:manage routing:manage sla:manage macro:manage
    contact:read contact:write contact:delete
    lead:read lead:write lead:delete
    deal:read deal:write deal:delete
    crm_config:manage
    activity:read activity:write
    pipeline:read pipeline:manage sequence:enroll
    work:read work:write project:manage
    report:operational report:sales report:export finance:read finance:write
    connector:read connector:operate connector:manage connector:invoke
    approval:review appeal:adjudicate decision:run
    knowledge:read knowledge:draft knowledge:review knowledge:publish knowledge:admin
    user:manage settings:manage audit:read tenant:manage
    service_account:manage api_token:manage webhook:manage
  ].freeze

  # ── Functional roles (the target model) ────────────────────────────────────
  # super_admin holds everything; the rest are least-privilege slices. Two
  # deliberate separation-of-duties choices: platform plumbing (settings:manage,
  # connector:manage, service_account:manage, ai:autonomy) is super_admin-only,
  # and approval:review (the human-of-record approval) never sits with a
  # purely-operational role (maker-checker).
  #
  # Tenancy: super_admin is the cross-tenant/platform tier, client_admin the
  # per-tenant org admin — that distinction is enforced in the SCOPING layer
  # (without_tenant), not here; this matrix is tenant-agnostic.
  FUNCTIONAL = {
    "super_admin" => PERMISSIONS,
    "client_admin" => %w[
      case:read case:write case:delete case:collaborate
      queue:manage routing:manage sla:manage macro:manage
      contact:read contact:write contact:delete
      lead:read lead:write lead:delete deal:read deal:write deal:delete
      crm_config:manage
      activity:read activity:write
      pipeline:read pipeline:manage sequence:enroll
      work:read work:write project:manage
      report:operational report:sales report:export finance:read finance:write
      approval:review appeal:adjudicate decision:run
      knowledge:read knowledge:draft knowledge:review knowledge:publish knowledge:admin
      connector:invoke
      user:manage audit:read
    ].freeze,
    "customer_service_supervisor" => %w[
      case:read case:write case:delete case:collaborate
      queue:manage routing:manage sla:manage macro:manage
      contact:read contact:write activity:read activity:write
      work:read work:write report:operational report:export
      knowledge:read connector:invoke
    ].freeze,
    "finance" => %w[
      case:read contact:read lead:read deal:read pipeline:read work:read activity:read
      report:operational report:sales report:export finance:read finance:write knowledge:read
    ].freeze,
    "sales" => %w[
      case:read contact:read contact:write
      lead:read lead:write deal:read deal:write pipeline:read
      activity:read activity:write
      sequence:enroll report:sales work:read knowledge:read
    ].freeze,
    "customer_service" => %w[
      case:read case:write case:collaborate contact:read contact:write
      work:read work:write activity:read activity:write
      report:operational knowledge:read connector:invoke
    ].freeze,
    "technical" => %w[
      case:read contact:read report:operational
      work:read work:write activity:read activity:write
      connector:read connector:operate knowledge:read webhook:manage
    ].freeze,
    "decision_reviewer" => %w[
      case:read contact:read lead:read deal:read activity:read work:read
      report:operational approval:review appeal:adjudicate decision:run
      knowledge:read audit:read
    ].freeze,
    "knowledge_manager" => %w[
      case:read contact:read activity:read
      knowledge:read knowledge:draft knowledge:review knowledge:publish knowledge:admin
    ].freeze,
    "auditor" => %w[
      case:read contact:read lead:read deal:read pipeline:read work:read activity:read
      report:operational report:sales report:export knowledge:read audit:read
    ].freeze,
    "readonly" => %w[
      case:read contact:read lead:read deal:read pipeline:read work:read report:sales activity:read knowledge:read
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
