require "test_helper"

class TenantTest < ActiveSupport::TestCase
  test "requires a name and a DNS-label slug" do
    assert Tenant.new(name: "Zeta", slug: "zeta").valid?
    refute Tenant.new(name: "", slug: "zeta").valid?
    refute Tenant.new(name: "Zeta", slug: "Zeta Corp").valid?
    refute Tenant.new(name: "Zeta", slug: "_bad").valid?
  end

  test "subdomain is optional (isolated singleton) but DNS-label-shaped when set" do
    assert Tenant.new(name: "Zeta", slug: "zeta", subdomain: nil).valid?
    assert Tenant.new(name: "Zeta", slug: "zeta", subdomain: "zeta").valid?
    refute Tenant.new(name: "Zeta", slug: "zeta", subdomain: "Bad Sub").valid?
  end

  test "slug and subdomain are unique across tenants" do
    refute Tenant.new(name: "Dup", slug: "primary").valid?
    refute Tenant.new(name: "Dup", slug: "zeta", subdomain: "acme").valid?
  end

  test "status defaults to active" do
    assert Tenant.new(name: "Zeta", slug: "zeta").active?
  end

  test "primary finds the seeded singleton by slug" do
    assert_equal tenants(:primary), Tenant.primary
  end

  test "deployment mode defaults to isolated" do
    assert Tenant.isolated_deployment?
    refute Tenant.shared_deployment?
  end
end
