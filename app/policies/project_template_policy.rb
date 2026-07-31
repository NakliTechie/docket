class ProjectTemplatePolicy < ApplicationPolicy
  def index?   = permit?("project:manage")
  def show?    = permit?("project:manage")
  def create?  = permit?("project:manage")
  def update?  = permit?("project:manage")
  def destroy? = permit?("project:manage")

  class Scope < Scope
    def resolve
      permit?("project:manage") ? scope.all : scope.none
    end
  end
end
