class ConnectorPolicy < ApplicationPolicy
  def index?   = permit?("connector:read")
  def show?    = permit?("connector:read")
  def new?     = permit?("connector:manage")
  def create?  = permit?("connector:manage")
  def edit?    = permit?("connector:manage")
  def update?  = permit?("connector:manage")
  def destroy? = permit?("connector:manage")

  class Scope < Scope
    def resolve
      permit?("connector:read") ? scope.all : scope.none
    end
  end
end
