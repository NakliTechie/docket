# The super_admin platform tier manages the fleet of tenants. tenant:manage is
# super_admin-only (it's in the full vocabulary, which only super_admin holds);
# a per-tenant client_admin cannot provision or suspend tenants.
class TenantPolicy < ApplicationPolicy
  def index?    = permit?("tenant:manage")
  def new?      = index?
  def create?   = permit?("tenant:manage")
  def suspend?  = permit?("tenant:manage")
  def activate? = permit?("tenant:manage")

  class Scope < Scope
    def resolve
      permit?("tenant:manage") ? scope.all : scope.none
    end
  end
end
