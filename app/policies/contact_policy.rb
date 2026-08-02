class ContactPolicy < ApplicationPolicy
  def index?   = permit?("contact:read")
  def show?    = permit?("contact:read") && record_in_scope?(:read)
  def create?  = permit?("contact:write")
  def update?  = permit?("contact:write") && record_in_scope?(:write)
  def destroy? = permit?("contact:delete") && record_in_scope?(:write)

  class Scope < Scope
    def resolve
      permit?("contact:read") ? record_scope : scope.none
    end
  end
end
