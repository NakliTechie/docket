# Running a sprint is planning work, not configuring the workspace: work:write
# starts and closes them, so a team lead doesn't need project:manage to run
# their own cadence.
class SprintPolicy < ApplicationPolicy
  def index?   = permit?("work:read")
  def show?    = permit?("work:read") && project_visible? && project_in_scope?(:read)
  def create?  = permit?("work:write") && project_visible? && project_in_scope?(:write)
  def update?  = create?
  def start?   = create?
  def close?   = create?
  def destroy? = permit?("project:manage") && project_visible? && project_in_scope?(:write)

  private

  def project_visible? = record.is_a?(Class) || record.project&.visible_to?(user) || false

  def project_in_scope?(access)
    record.is_a?(Class) || RecordVisibility.allowed?(user, record.project, access: access)
  end

  class Scope < Scope
    def resolve
      return scope.none unless permit?("work:read")

      projects = RecordVisibility.resolve(user, Project.visible_to(user), access: :read)
      scope.where(project_id: projects.select(:id))
    end
  end
end
