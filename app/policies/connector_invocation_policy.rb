# Who may review the effector queue and act as the human-of-record on a
# proposed agent action — the approval-review tier. Everyone else is denied
# (default-deny via ApplicationPolicy). Kept at admin tier so initiation
# (connector:invoke) and approval can't collapse into one role (maker-checker).
class ConnectorInvocationPolicy < ApplicationPolicy
  def index?   = permit?("approval:review")
  def show?    = permit?("approval:review")
  def approve? = permit?("approval:review")
  def reject?  = permit?("approval:review")

  class Scope < Scope
    def resolve
      permit?("approval:review") ? scope.all : scope.none
    end
  end
end
