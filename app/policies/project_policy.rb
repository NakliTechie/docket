# Projects split the same way the case desk does: doing the work (work:write)
# is separate from configuring the workspace (project:manage) — an engineer
# moves items, an admin creates projects and edits workflow states.
class ProjectPolicy < ApplicationPolicy
  def index?   = permit?("work:read")
  def show?    = permit?("work:read")
  def create?  = permit?("project:manage")
  def update?  = permit?("project:manage")
  def destroy? = permit?("project:manage")
  def archive? = permit?("project:manage")

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.all : scope.none
    end
  end
end
