require "test_helper"

class TenantTest < ActiveSupport::TestCase
  test "requires a name and a DNS-label slug" do
    assert Tenant.new(name: "Acme", slug: "acme").valid?
    refute Tenant.new(name: "", slug: "acme").valid?
    refute Tenant.new(name: "Acme", slug: "Acme Corp").valid?
    refute Tenant.new(name: "Acme", slug: "_bad").valid?
  end

  test "subdomain is optional (isolated singleton) but DNS-label-shaped when set" do
    assert Tenant.new(name: "Acme", slug: "acme", subdomain: nil).valid?
    assert Tenant.new(name: "Acme", slug: "acme", subdomain: "acme").valid?
    refute Tenant.new(name: "Acme", slug: "acme", subdomain: "Bad Sub").valid?
  end

  test "slug and subdomain are unique" do
    Tenant.create!(name: "One", slug: "one", subdomain: "one")
    refute Tenant.new(name: "Dup", slug: "one").valid?
    refute Tenant.new(name: "Dup", slug: "two", subdomain: "one").valid?
  end

  test "status defaults to active" do
    assert Tenant.new(name: "Acme", slug: "acme").active?
  end

  test "primary finds the seeded singleton by slug" do
    primary = Tenant.create!(name: "Docket", slug: Tenant::PRIMARY_SLUG)
    Tenant.create!(name: "Other", slug: "other")
    assert_equal primary, Tenant.primary
  end

  test "deployment mode defaults to isolated" do
    assert Tenant.isolated_deployment?
    refute Tenant.shared_deployment?
  end
end
