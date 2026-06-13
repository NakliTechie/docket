class PipelinePolicy < ApplicationPolicy
  # Pipelines are funnel configuration — staff can view, admins manage.
  def index?   = permit?("pipeline:read")
  def show?    = permit?("pipeline:read")
  def create?  = permit?("pipeline:manage")
  def update?  = permit?("pipeline:manage")
  def destroy? = permit?("pipeline:manage")

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
