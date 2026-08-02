class BusinessCalendarPolicy < ApplicationPolicy
  def index?   = permit?("case:read")
  def show?    = permit?("case:read")
  def create?  = permit?("sla:manage")
  def update?  = permit?("sla:manage")
  def destroy? = permit?("sla:manage")

  class Scope < Scope
    def resolve
      permit?("case:read") ? scope.all : scope.none
    end
  end
end
