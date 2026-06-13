# Resolves the request's tenant and makes it the ambient scope BEFORE anything
# else runs (prepend) — tenant context must exist before any query, including
# session lookup. Tenant comes from the HOST, not the session, so the public
# portal and inbound webhooks are tenant-correct even with no signed-in user.
#
#   isolated → the singleton primary tenant (scoping is then a no-op predicate).
#   shared   → resolved from the subdomain (full missing-tenant handling lands
#              in Phase C; default mode is isolated so this branch is dormant).
module TenantResolution
  extend ActiveSupport::Concern

  included do
    prepend_before_action :resolve_tenant
  end

  private

  def resolve_tenant
    if Tenant.shared_deployment?
      tenant = Tenant.active.find_by(subdomain: request.subdomain.presence)
      return head(:not_found) if tenant.nil? # unknown subdomain → no app here
    else
      tenant = Tenant.primary
    end

    Current.tenant = tenant
    ActsAsTenant.current_tenant = tenant
  end
end
