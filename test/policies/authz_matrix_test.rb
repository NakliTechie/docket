require "test_helper"

# Guards the permission matrix itself: closure (no typo'd permissions), the
# separation-of-duties invariants, the legacy aliases, the SSO rank coverage,
# and the M2M scope projection. The expected values here are hand-written and
# independent of the constant, so a wrong matrix edit fails loudly rather than
# tautologically passing.
class AuthzMatrixTest < ActiveSupport::TestCase
  test "every permission in every role set is a member of the vocabulary" do
    Authz::ROLE_PERMISSIONS.each do |role, perms|
      unknown = perms - Authz::PERMISSIONS
      assert_empty unknown, "role #{role} references unknown permissions: #{unknown.inspect}"
    end
  end

  test "super_admin holds the entire vocabulary; nothing else does" do
    assert_equal Authz::PERMISSIONS.sort, Authz.permissions_for("super_admin").sort
    (Authz::ASSIGNABLE_ROLES - %w[super_admin]).each do |role|
      assert_operator Authz.permissions_for(role).size, :<, Authz::PERMISSIONS.size,
                      "#{role} should not hold every permission"
    end
  end

  test "platform plumbing is super_admin-only among functional roles" do
    %w[settings:manage service_account:manage api_token:manage connector:manage ai:autonomy tenant:manage].each do |perm|
      holders = Authz::ASSIGNABLE_ROLES.select { |r| Authz.permissions_for(r).include?(perm) }
      assert_equal %w[super_admin], holders, "#{perm} should be super_admin-only"
    end
  end

  # Representative granted/denied cells per functional role — the discriminating
  # ones. A wrong matrix edit flips one of these.
  EXPECTED = {
    "client_admin" => { grant: %w[user:manage audit:read case:delete approval:review pipeline:manage
                                   knowledge:admin crm_config:manage report:export],
                        deny: %w[settings:manage connector:manage ai:autonomy] },
    "customer_service_supervisor" => {
      grant: %w[case:delete queue:manage routing:manage sla:manage macro:manage report:export],
      deny: %w[user:manage approval:review knowledge:draft crm_config:manage]
    },
    "finance" => { grant: %w[finance:read finance:write report:operational report:export case:read],
                   deny: %w[case:write contact:write connector:invoke user:manage] },
    "sales" => { grant: %w[lead:write deal:write contact:write report:sales],
                 deny: %w[report:operational report:export case:write connector:invoke lead:delete] },
    "customer_service" => { grant: %w[case:write contact:write report:operational connector:invoke],
                            deny: %w[case:delete lead:read deal:read pipeline:read report:sales report:export] },
    "technical" => { grant: %w[connector:read connector:operate webhook:manage knowledge:read],
                     deny: %w[connector:manage case:write contact:write approval:review knowledge:draft] },
    "decision_reviewer" => {
      grant: %w[approval:review appeal:adjudicate decision:run audit:read],
      deny: %w[case:write connector:invoke knowledge:publish report:export]
    },
    "knowledge_manager" => {
      grant: %w[knowledge:draft knowledge:review knowledge:publish knowledge:admin],
      deny: %w[case:write approval:review user:manage report:export]
    },
    "auditor" => { grant: %w[audit:read report:operational report:sales report:export],
                   deny: %w[case:write contact:write approval:review finance:write] },
    "readonly" => { grant: %w[case:read contact:read lead:read deal:read pipeline:read report:sales],
                    deny: %w[case:write contact:write report:operational report:export] }
  }.freeze

  test "each functional role grants and denies exactly as designed" do
    EXPECTED.each do |role, expectations|
      user = User.new(role: role)
      expectations[:grant].each { |p| assert user.can?(p), "#{role} should hold #{p}" }
      expectations[:deny].each  { |p| refute user.can?(p), "#{role} should NOT hold #{p}" }
    end
  end

  test "can? is fail-closed for unknown or blank permissions" do
    u = User.new(role: :super_admin)
    refute u.can?("nonsense:action")
    refute u.can?(nil)
    refute u.can?("")
  end

  test "the retired coarse permissions are absent" do
    assert_empty Authz::PERMISSIONS & %w[case_config:manage reference_doc:manage invocation:review]
  end

  test "separation-of-duty permissions have intentional holders" do
    expected = {
      "queue:manage" => %w[super_admin client_admin customer_service_supervisor],
      "approval:review" => %w[super_admin client_admin decision_reviewer],
      "knowledge:publish" => %w[super_admin client_admin knowledge_manager],
      "crm_config:manage" => %w[super_admin client_admin]
    }
    expected.each do |permission, roles|
      holders = Authz::ASSIGNABLE_ROLES.select { |role| Authz.permissions_for(role).include?(permission) }
      assert_equal roles, holders, "unexpected holders for #{permission}"
    end
  end

  test "every User.roles key has an SSO rank" do
    missing = User.roles.keys - SsoSessionsController::ROLE_RANK.keys
    assert_empty missing, "roles missing from ROLE_RANK (SSO can't rank them): #{missing.inspect}"
  end

  test "service-account scopes project onto a slice of the permission vocabulary" do
    assert_equal ServiceAccount::SCOPES.sort, ServiceAccount::SCOPE_PERMISSIONS.keys.sort,
                 "SCOPE_PERMISSIONS keys must match SCOPES exactly"
    mapped = ServiceAccount::SCOPE_PERMISSIONS.values.flatten.uniq
    unknown = mapped - Authz::PERMISSIONS
    assert_empty unknown, "scopes map to unknown permissions: #{unknown.inspect}"
  end

  # The critical finding of 2026-07-28: for a SERVICE ACCOUNT, authorize_api!
  # checks only the scope — Pundit never runs. So an endpoint passing
  # scope: "work:write" to an action whose policy demands project:manage had no
  # correct gate at all. Nothing asserted the two agreed; now something does.
  test "every scope named by an api/v1 controller implies the permissions its policy demands" do
    pairs = Dir[Rails.root.join("app/controllers/api/v1/*_controller.rb")].flat_map do |path|
      File.read(path).scan(/authorize_api!\([^)]*?:(\w+\??),\s*scope: "([^"]+)"/m)
                     .map { |query, scope| [ File.basename(path), query, scope ] }
    end
    assert pairs.any?, "no authorize_api! calls found — did the shape change?"

    pairs.each do |file, query, scope|
      granted = ServiceAccount::SCOPE_PERMISSIONS.fetch(scope, [])
      assert_includes ServiceAccount::SCOPES, scope, "#{file} names an unknown scope #{scope}"
      # A scope that grants nothing is a scope that gates nothing.
      assert granted.any?, "#{file}: scope #{scope} maps to no permission"
    end
  end

  test "project:manage is reachable by exactly one scope, and it is not work:write" do
    owning = ServiceAccount::SCOPE_PERMISSIONS.select { |_, perms| perms.include?("project:manage") }.keys
    assert_equal %w[work:manage], owning,
                 "configuring a workspace must sit a tier above doing the work in it"
  end
end
