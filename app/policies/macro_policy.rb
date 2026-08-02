class MacroPolicy < ApplicationPolicy
  def index?   = permit?("case:read")
  def show?    = permit?("case:read")
  def create?  = permit?("macro:manage")
  def update?  = permit?("macro:manage")
  def destroy? = permit?("macro:manage")

  class Scope < Scope
    def resolve
      permit?("case:read") ? scope.all : scope.none
    end
  end
end
