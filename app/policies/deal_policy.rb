class DealPolicy < ApplicationPolicy
  def index?   = permit?("deal:read")
  def show?    = permit?("deal:read")
  def create?  = permit?("deal:write")
  def update?  = permit?("deal:write")
  def move?    = permit?("deal:write")
  def destroy? = permit?("deal:delete")

  class Scope < Scope
    def resolve
      permit?("deal:read") ? scope.all : scope.none
    end
  end
end
