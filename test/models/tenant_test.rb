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

  test "shared mode never maps an apex host to the isolated primary tenant" do
    original = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    assert_nil Tenant.resolve_by_subdomain(nil)
    assert_nil Tenant.resolve_by_subdomain("")
    assert_equal tenants(:acme), Tenant.resolve_by_subdomain("acme")
  ensure
    Rails.application.config.x.tenancy_mode = original
  end

  test "shared host resolution honors a multi-label base domain" do
    original_mode = Rails.application.config.x.tenancy_mode
    original_domain = ENV["DOCKET_BASE_DOMAIN"]
    Rails.application.config.x.tenancy_mode = "shared"
    ENV["DOCKET_BASE_DOMAIN"] = "docket.co.in"

    assert_equal tenants(:acme), Tenant.resolve_by_host("acme.docket.co.in")
    assert_nil Tenant.resolve_by_host("docket.co.in")
    assert_nil Tenant.resolve_by_host("nested.acme.docket.co.in")
    assert_nil Tenant.resolve_by_host("acme.attacker.test")
  ensure
    Rails.application.config.x.tenancy_mode = original_mode
    ENV["DOCKET_BASE_DOMAIN"] = original_domain
  end
end
