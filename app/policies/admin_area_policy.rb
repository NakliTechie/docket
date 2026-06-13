# Headless policy for the read-only admin oversight surfaces not backed by a
# single record: audit status (show), activity & usage (index), security events
# (index). All gated on audit:read (super_admin + client_admin). The mutating
# platform surfaces (settings, service accounts, API tokens, webhooks) moved to
# PlatformAreaPolicy, which gates each on its own manage-permission.
class AdminAreaPolicy < ApplicationPolicy
  def index? = permit?("audit:read")
  def show?  = permit?("audit:read")
end
