# Who may review the effector queue and act as the human-of-record on a
# proposed agent action — the invocation:review tier. Everyone else is denied
# (default-deny via ApplicationPolicy). Kept at admin tier so initiation
# (connector:invoke) and approval can't collapse into one role (maker-checker).
class ConnectorInvocationPolicy < ApplicationPolicy
  def index?   = permit?("invocation:review")
  def show?    = permit?("invocation:review")
  def approve? = permit?("invocation:review")
  def reject?  = permit?("invocation:review")

  class Scope < Scope
    def resolve
      permit?("invocation:review") ? scope.all : scope.none
    end
  end
end
