class WorkItemPolicy < ApplicationPolicy
  def index?      = permit?("work:read")
  def show?       = permit?("work:read") && project_visible?
  def create?     = permit?("work:write") && project_visible?
  def update?     = permit?("work:write") && project_visible?
  def transition? = permit?("work:write") && project_visible?
  def watch?      = permit?("work:read") && project_visible?
  # No work:delete in the vocabulary — removing work is a workspace-config act,
  # same call as archiving a project.
  def destroy?    = permit?("project:manage") && project_visible?

  private

  def project_visible? = record.is_a?(Class) || record.project&.visible_to?(user) || false

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.visible_to(user) : scope.none
    end
  end
end
