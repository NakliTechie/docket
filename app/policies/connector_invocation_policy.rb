# Who may review the effector queue and act as the human-of-record on a
# proposed agent action. Admins and supervisors hold that authority;
# everyone else is denied (default-deny via ApplicationPolicy).
class ConnectorInvocationPolicy < ApplicationPolicy
  def index?   = admin? || supervisor?
  def show?    = admin? || supervisor?
  def approve? = admin? || supervisor?
  def reject?  = admin? || supervisor?

  class Scope < Scope
    def resolve
      admin? || supervisor? ? scope.all : scope.none
    end
  end
end
