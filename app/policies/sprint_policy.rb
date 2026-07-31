# Running a sprint is planning work, not configuring the workspace: work:write
# starts and closes them, so a team lead doesn't need project:manage to run
# their own cadence.
class SprintPolicy < ApplicationPolicy
  def index?   = permit?("work:read")
  def show?    = permit?("work:read") && project_visible?
  def create?  = permit?("work:write") && project_visible?
  def update?  = permit?("work:write") && project_visible?
  def start?   = permit?("work:write") && project_visible?
  def close?   = permit?("work:write") && project_visible?
  def destroy? = permit?("project:manage") && project_visible?

  private

  def project_visible? = record.is_a?(Class) || record.project&.visible_to?(user) || false

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.visible_to(user) : scope.none
    end
  end
end
