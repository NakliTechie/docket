class CategoryPolicy < ApplicationPolicy
  def index?   = staff?
  def show?    = staff?
  def create?  = admin? || supervisor?
  def update?  = admin? || supervisor?
  def destroy? = admin? || supervisor?

  # Granting the AI autonomous resolution is admin-only.
  def toggle_auto_resolve? = admin?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
