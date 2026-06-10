class MacroPolicy < ApplicationPolicy
  def index?   = staff?
  def create?  = admin? || supervisor?
  def update?  = admin? || supervisor?
  def destroy? = admin? || supervisor?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
