# Running a sprint is planning work, not configuring the workspace: work:write
# starts and closes them, so a team lead doesn't need project:manage to run
# their own cadence.
class SprintPolicy < ApplicationPolicy
  def index?   = permit?("work:read")
  def show?    = permit?("work:read")
  def create?  = permit?("work:write")
  def update?  = permit?("work:write")
  def start?   = permit?("work:write")
  def close?   = permit?("work:write")
  def destroy? = permit?("project:manage")

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.all : scope.none
    end
  end
end
