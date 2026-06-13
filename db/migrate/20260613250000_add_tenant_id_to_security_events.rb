# H1 (forward pass 2026-06-13): the SecurityEvent log (failed/throttled logins,
# SSO rejections) had no tenant column, so the admin view leaked every tenant's
# failed-login emails/IPs in shared mode. Add a nullable tenant_id filter column
# (stamped from the resolved tenant at record time; nullable because some auth
# events have no resolvable tenant). Like AuditEntry, NOT acts_as_tenant — the
# write must never raise from the auth path.
class AddTenantIdToSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :security_events, :tenant, null: true, foreign_key: true
  end
end
