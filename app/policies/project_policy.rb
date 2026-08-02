# Projects split the same way the case desk does: doing the work (work:write)
# is separate from configuring the workspace (project:manage) — an engineer
# moves items, an admin creates projects and edits workflow states.
class ProjectPolicy < ApplicationPolicy
  def index?   = permit?("work:read")
  def show?    = permit?("work:read") && record.visible_to?(user) && record_in_scope?(:read)
  def create?  = permit?("project:manage")
  def update?  = permit?("project:manage") && record_in_scope?(:write)
  def destroy? = update?
  def archive? = update?

  class Scope < Scope
    def resolve
      permit?("work:read") ? record_scope.merge(scope.visible_to(user)) : scope.none
    end
  end
end
