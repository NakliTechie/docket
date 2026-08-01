# Activities are a CRM/desk interaction log — gated on activity:read/write
# (held by sales, customer_service, technical, client_admin, super_admin;
# read-only for finance/readonly).
class ActivityPolicy < ApplicationPolicy
  def index?    = permit?("activity:read")
  def show?     = permit?("activity:read")
  def create?   = permit?("activity:write")
  def update?   = permit?("activity:write")
  def complete? = permit?("activity:write")
  def destroy?  = permit?("activity:write")

  class Scope < Scope
    def resolve
      permit?("activity:read") ? scope.all : scope.none
    end
  end
end
