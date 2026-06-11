class PipelinePolicy < ApplicationPolicy
  # Pipelines are funnel configuration — staff can view, admins manage.
  def index?   = staff?
  def show?    = staff?
  def create?  = admin?
  def update?  = admin?
  def destroy? = admin?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
