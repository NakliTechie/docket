# Deployment topology for the tenancy seam. The SAME codebase serves both:
#
#   isolated (default) — one database per client. Exactly one tenant row; tenant
#       scoping is a constant predicate, so "your data, your DB, no other
#       client's rows" stays literally true. This is the sovereign procurement
#       asset and the default.
#   shared             — many tenants on shared infra, resolved by subdomain
#       (e.g. acme.docket.app). For SMBs who can't fund a dedicated instance.
#
# Set via DOCKET_DEPLOYMENT_MODE=isolated|shared. Read through
# Tenant.deployment_mode / Tenant.shared_deployment?.
Rails.application.config.x.tenancy_mode = ENV.fetch("DOCKET_DEPLOYMENT_MODE", "isolated")

# Fail-closed exactly where a missed scope is a data-confidentiality breach:
# SHARED deploys raise NoTenantSet on any unscoped query/write. ISOLATED deploys
# (one tenant) are lenient — an unscoped read returns the same single tenant's
# rows, so there's nothing to leak, and we avoid forcing a tenant onto every
# rake/console path. Creates still set tenant_id wherever a tenant is in scope.
ActsAsTenant.configure do |config|
  config.require_tenant = -> { Tenant.shared_deployment? }
end
