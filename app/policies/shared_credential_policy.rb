class SharedCredentialPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = admin?
  def new?     = admin?
  def create?  = admin?
  def edit?    = admin?
  def update?  = admin?
  def destroy? = admin?

  class Scope < Scope
    def resolve
      admin? ? scope.all : scope.none
    end
  end
end
