# Activities are a CRM/desk interaction log — gated on activity:read/write
# (held by sales, customer_service, technical, client_admin, super_admin;
# read-only for finance/readonly).
class ActivityPolicy < ApplicationPolicy
  def index?    = permit?("activity:read")
  def show?     = permit?("activity:read") && record_in_scope?(:read)
  def create?
    permit?("activity:write") && record.subject.present? &&
      RecordVisibility.allowed?(user, record.subject, access: :write)
  end
  def update?   = permit?("activity:write") && record_in_scope?(:write)
  def complete? = update?
  def destroy?  = update?

  class Scope < Scope
    def resolve
      permit?("activity:read") ? record_scope : scope.none
    end
  end
end
