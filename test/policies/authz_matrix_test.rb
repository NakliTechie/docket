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
    "client_admin" => { grant: %w[user:manage audit:read case:delete invocation:review pipeline:manage],
                        deny: %w[settings:manage connector:manage ai:autonomy] },
    "finance" => { grant: %w[finance:read finance:write report:operational case:read],
                   deny: %w[case:write contact:write connector:invoke user:manage] },
    "sales" => { grant: %w[lead:write deal:write contact:write report:sales],
                 deny: %w[report:operational case:write connector:invoke lead:delete] },
    "customer_service" => { grant: %w[case:write contact:write report:operational connector:invoke],
                            deny: %w[case:delete lead:read deal:read pipeline:read report:sales] },
    "technical" => { grant: %w[connector:read connector:operate webhook:manage reference_doc:manage],
                     deny: %w[connector:manage case:write contact:write invocation:review] },
    "readonly" => { grant: %w[case:read contact:read lead:read deal:read pipeline:read report:sales],
                    deny: %w[case:write contact:write report:operational] }
  }.freeze

  test "each functional role grants and denies exactly as designed" do
    EXPECTED.each do |role, expectations|
      user = User.new(role: role)
      expectations[:grant].each { |p| assert user.can?(p), "#{role} should hold #{p}" }
      expectations[:deny].each  { |p| refute user.can?(p), "#{role} should NOT hold #{p}" }
    end
  end

  # Transition safety: legacy roles reproduce TODAY's authority. admin == the
  # full set; supervisor/agent are explicit sets (NOT their functional successors).
  test "legacy admin holds the full vocabulary" do
    assert_equal Authz::PERMISSIONS.sort, Authz.permissions_for("admin").sort
  end

  test "legacy supervisor matches the old admin-or-supervisor authority" do
    u = User.new(role: :supervisor)
    %w[case:delete case_config:manage invocation:review reference_doc:manage
       report:operational connector:invoke contact:delete lead:delete deal:delete].each do |p|
      assert u.can?(p), "legacy supervisor should hold #{p}"
    end
    # supervisor was NOT a user-manager / platform admin / pipeline-manager today.
    %w[user:manage audit:read settings:manage connector:manage connector:read
       pipeline:manage ai:autonomy finance:read].each do |p|
      refute u.can?(p), "legacy supervisor should NOT hold #{p}"
    end
  end

  test "legacy agent matches the old can_work authority (restricted)" do
    u = User.new(role: :agent)
    %w[case:write contact:write lead:write deal:write pipeline:read sequence:enroll report:sales].each do |p|
      assert u.can?(p), "legacy agent should hold #{p}"
    end
    # agent could not delete, manage config, see the operational dashboard, or invoke.
    %w[case:delete contact:delete case_config:manage report:operational connector:invoke
       reference_doc:manage invocation:review].each do |p|
      refute u.can?(p), "legacy agent should NOT hold #{p}"
    end
  end

  test "can? is fail-closed for unknown or blank permissions" do
    u = User.new(role: :super_admin)
    refute u.can?("nonsense:action")
    refute u.can?(nil)
    refute u.can?("")
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
end
