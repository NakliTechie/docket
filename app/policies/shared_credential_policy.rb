class SharedCredentialPolicy < ApplicationPolicy
  # Stored credentials are platform plumbing — super_admin-tier, via the same
  # connector:manage permission that gates connector configuration.
  def index?   = permit?("connector:manage")
  def show?    = permit?("connector:manage")
  def new?     = permit?("connector:manage")
  def create?  = permit?("connector:manage")
  def edit?    = permit?("connector:manage")
  def update?  = permit?("connector:manage")
  def destroy? = permit?("connector:manage")

  class Scope < Scope
    def resolve
      permit?("connector:manage") ? scope.all : scope.none
    end
  end
end
