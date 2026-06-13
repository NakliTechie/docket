# Idempotent base seeds: the primary tenant, a break-glass admin account, and
# the day-one defaults floor. Rich demo data ships separately (db/seeds/demo.rb).
#
# The primary tenant is the isolated-deploy singleton — every deployment has one
# (a shared deploy provisions further tenants via Tenants::Provisioner). Tenant
# scoping resolves to it on the isolated path. No subdomain (isolated deploys
# serve a single host).
primary_tenant = Tenant.find_or_create_by!(slug: Tenant::PRIMARY_SLUG) do |t|
  t.name = ENV["DOCKET_TENANT_NAME"].presence || "Docket"
end

ActsAsTenant.with_tenant(primary_tenant) do
  # The admin password comes from DOCKET_ADMIN_PASSWORD. If unset, we generate a
  # random one and print it ONCE on creation — never ship a known default (this
  # is a public repo). The password is only applied when the account is first
  # created, so re-running seeds never resets it.
  admin_password = ENV["DOCKET_ADMIN_PASSWORD"].presence || SecureRandom.alphanumeric(24)
  admin_created = false

  admin = User.find_or_create_by!(email_address: "admin@docket.local") do |user|
    user.name = "Docket Admin"
    user.role = :super_admin # break-glass: the platform tier (does everything)
    user.password = admin_password
    admin_created = true
  end

  if admin_created
    puts "Seeded break-glass admin: #{admin.email_address}"
    if ENV["DOCKET_ADMIN_PASSWORD"].blank?
      puts "  Generated password (shown once — change it after first login): #{admin_password}"
    end
  end

  # Day-one floor (pipeline + ticket queue + SLA), shared with tenant provisioning.
  Tenants::Defaults.seed!
end
