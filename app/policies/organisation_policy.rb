class OrganisationPolicy < ApplicationPolicy
  def index?   = staff?
  def show?    = staff?
  def create?  = can_work?
  def update?  = can_work?
  def destroy? = admin? || supervisor?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
