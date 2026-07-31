# The super_admin platform tier manages the fleet of tenants. tenant:manage is
# super_admin-only (it's in the full vocabulary, which only super_admin holds);
# a per-tenant client_admin cannot provision or suspend tenants.
class TenantPolicy < ApplicationPolicy
  def index?    = permit?("tenant:manage")
  def new?      = index? && Tenant.shared_deployment?
  def create?   = new?
  def suspend?  = permit?("tenant:manage")
  def activate? = permit?("tenant:manage")
  # Entitlements are packaging, not per-tenant configuration: only the platform
  # tier sets them, never a client_admin inside the tenant being packaged.
  def entitlements?        = permit?("tenant:manage")
  def update_entitlements? = permit?("tenant:manage")

  class Scope < Scope
    def resolve
      permit?("tenant:manage") ? scope.all : scope.none
    end
  end
end
