# Board columns are workspace configuration.
class WorkflowStatePolicy < ApplicationPolicy
  def index?   = permit?("work:read")
  def create?  = permit?("project:manage")
  def update?  = permit?("project:manage")
  def destroy? = permit?("project:manage")

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.all : scope.none
    end
  end
end
