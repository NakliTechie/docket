class WorkItemPolicy < ApplicationPolicy
  def index?      = permit?("work:read")
  def show?       = permit?("work:read")
  def create?     = permit?("work:write")
  def update?     = permit?("work:write")
  def transition? = permit?("work:write")
  def watch?      = permit?("work:read")
  # No work:delete in the vocabulary — removing work is a workspace-config act,
  # same call as archiving a project.
  def destroy?    = permit?("project:manage")

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.all : scope.none
    end
  end
end
