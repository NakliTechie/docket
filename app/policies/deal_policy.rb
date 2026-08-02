class DealPolicy < ApplicationPolicy
  def index?   = permit?("deal:read")
  def show?    = permit?("deal:read") && record_in_scope?(:read)
  def create?  = permit?("deal:write")
  def update?  = permit?("deal:write") && record_in_scope?(:write)
  def move?    = update?
  def onboard? = update? && permit?("project:manage")
  def engage?  = onboard?
  def destroy? = permit?("deal:delete") && record_in_scope?(:write)

  class Scope < Scope
    def resolve
      permit?("deal:read") ? record_scope : scope.none
    end
  end
end
