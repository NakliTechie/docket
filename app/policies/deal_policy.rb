class DealPolicy < ApplicationPolicy
  def index?   = permit?("deal:read")
  def show?    = permit?("deal:read")
  def create?  = permit?("deal:write")
  def update?  = permit?("deal:write")
  def move?    = permit?("deal:write")
  def onboard? = permit?("deal:write") && permit?("project:manage")
  def engage?  = onboard?
  def destroy? = permit?("deal:delete")

  class Scope < Scope
    def resolve
      permit?("deal:read") ? scope.all : scope.none
    end
  end
end
