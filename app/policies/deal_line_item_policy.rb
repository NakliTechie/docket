class DealLineItemPolicy < ApplicationPolicy
  def create?  = permit?("deal:write")
  def update?  = permit?("deal:write")
  def destroy? = permit?("deal:write")

  class Scope < Scope
    def resolve
      permit?("deal:read") ? scope.all : scope.none
    end
  end
end
