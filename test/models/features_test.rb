require "test_helper"

# The entitlement layer: the registry itself, per-tenant resolution, and the
# intersection with Authz. The controller-side guard is covered in
# test/controllers/feature_gating_test.rb.
class FeaturesTest < ActiveSupport::TestCase
  # ── Registry integrity ────────────────────────────────────────────────────
  test "every registry key is a module or a module.feature whose module exists" do
    Features::KEYS.each do |key|
      module_key = key.split(".", 2).first
      assert_includes Features::REGISTRY.keys, module_key,
                      "#{key} hangs off #{module_key}, which is not itself a feature"
    end
  end

  test "every permission a feature owns is a real Authz permission" do
    Features::REGISTRY.each do |key, permissions|
      permissions.each do |permission|
        assert_includes Authz::PERMISSIONS, permission,
                        "#{key} claims #{permission}, which is not in the Authz vocabulary"
      end
    end
  end

  test "no permission is owned by two features" do
    owned = Features::REGISTRY.values.flatten
    assert_equal owned.uniq.size, owned.size, "a permission is claimed by more than one feature"
  end

  test "presets name only real features" do
    Features::PRESETS.each do |name, disabled|
      disabled.each { |key| assert Features.exists?(key), "preset #{name} disables unknown #{key}" }
    end
  end

  test "chain walks module then feature; unknown key yields an empty chain" do
    assert_equal [ "crm" ], Features.chain("crm")
    assert_equal [ "crm", "crm.sequences" ], Features.chain("crm.sequences")
    assert_empty Features.chain("nope")
    assert_empty Features.chain("crm.nope")
  end

  # ── Per-tenant resolution ─────────────────────────────────────────────────
  test "a tenant with no overrides has everything on (the existing-deploy invariant)" do
    tenant = tenants(:primary)
    assert_empty tenant.entitlements
    Features::KEYS.each { |key| assert tenant.feature?(key), "#{key} should default on" }
  end

  test "unknown keys fail closed" do
    refute tenants(:primary).feature?("nope")
    refute tenants(:primary).feature?("work.nope")
    refute tenants(:primary).feature?(nil)
  end

  test "disabling a module disables its sub-features without naming them" do
    tenant = tenants(:acme)
    tenant.set_feature!("crm", false)

    refute tenant.feature?("crm")
    refute tenant.feature?("crm.sequences"), "a sub-feature of a dead module must be dead"
    assert tenant.feature?("service_desk"), "unrelated modules are untouched"
  end

  test "a sub-feature can be off while its module stays on" do
    tenant = tenants(:acme)
    tenant.set_feature!("crm.sequences", false)

    assert tenant.feature?("crm")
    refute tenant.feature?("crm.sequences")
  end

  test "re-enabling prunes the override rather than storing true" do
    tenant = tenants(:acme)
    tenant.set_feature!("work", false)
    assert_equal({ "work" => false }, tenant.entitlements)

    tenant.set_feature!("work", true)
    assert_empty tenant.entitlements, "defaults must keep flowing through, not be frozen as true"
    assert tenant.feature?("work")
  end

  test "set_feature! rejects unknown keys" do
    assert_raises(ArgumentError) { tenants(:acme).set_feature!("nope", false) }
  end

  test "entitlements referring to unknown features are invalid" do
    tenant = tenants(:acme)
    tenant.entitlements = { "not_a_feature" => false }
    refute tenant.valid?
    assert_match(/not_a_feature/, tenant.errors.full_messages.join)
  end

  test "presets apply as a whole set" do
    tenant = tenants(:acme)
    tenant.apply_preset!("service_only")

    assert tenant.feature?("service_desk")
    assert tenant.feature?("service_desk.kb")
    refute tenant.feature?("crm")
    refute tenant.feature?("work")

    tenant.apply_preset!("full")
    Features::KEYS.each { |key| assert tenant.feature?(key), "full preset should enable #{key}" }
  end

  # ── Ambient resolution ────────────────────────────────────────────────────
  test "Features.enabled? reads the tenant in scope" do
    tenants(:acme).set_feature!("work", false)

    ActsAsTenant.with_tenant(tenants(:acme)) { refute Features.enabled?("work") }
    ActsAsTenant.with_tenant(tenants(:primary)) { assert Features.enabled?("work") }
  end

  test "with no tenant resolved, entitlements do not apply but unknown keys still fail" do
    ActsAsTenant.without_tenant do
      assert Features.enabled?("work")
      refute Features.enabled?("nope")
    end
  end

  # ── Intersection with Authz ───────────────────────────────────────────────
  test "can? requires BOTH the role permission and the tenant entitlement" do
    admin = users(:admin) # super_admin — holds every permission
    assert admin.can?("lead:read")

    ActsAsTenant.current_tenant.set_feature!("crm", false)
    refute admin.can?("lead:read"), "a module the tenant doesn't have is not reachable by any role"
    assert admin.can?("case:read"), "unrelated modules stay reachable"
  end

  test "permissions no module owns are unaffected by entitlements" do
    admin = users(:admin)
    ActsAsTenant.current_tenant.apply_preset!("service_only")

    assert admin.can?("user:manage"), "deploy plumbing is not a purchasable module"
    assert admin.can?("audit:read")
    assert admin.can?("contact:read"), "contacts are shared by every module"
  end

  test "entitlements cannot grant a permission the role lacks" do
    readonly = users(:readonly)
    refute readonly.can?("case:write")

    ActsAsTenant.current_tenant.apply_preset!("full")
    refute readonly.can?("case:write"), "entitlements widen nothing — they only subtract"
  end
end
