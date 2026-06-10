class UserPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = admin? || record.id == user&.id
  def create?  = admin?
  def update?  = admin?
  def destroy? = admin? && record.id != user.id

  class Scope < Scope
    def resolve
      admin? ? scope.all : scope.none
    end
  end
end
