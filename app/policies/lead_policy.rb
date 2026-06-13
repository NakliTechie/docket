class LeadPolicy < ApplicationPolicy
  def index?   = permit?("lead:read")
  def show?    = permit?("lead:read")
  def create?  = permit?("lead:write")
  def update?  = permit?("lead:write")
  def convert? = permit?("lead:write")
  def mark_unqualified? = permit?("lead:write")
  def destroy? = permit?("lead:delete")

  class Scope < Scope
    def resolve
      permit?("lead:read") ? scope.all : scope.none
    end
  end
end
