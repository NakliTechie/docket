class SequencePolicy < ApplicationPolicy
  # Sequence definitions are admin-managed config; enrolling targets is
  # operational work any agent can do.
  def index?   = staff?
  def show?    = staff?
  def create?  = admin?
  def update?  = admin?
  def destroy? = admin?
  def enroll?  = can_work?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
