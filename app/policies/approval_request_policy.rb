# Acting on a maker-checker request is the human-of-record activity — same tier
# as the effector approval queue.
class ApprovalRequestPolicy < ApplicationPolicy
  def index?   = permit?("approval:review")
  def approve? = permit?("approval:review")
  def reject?  = permit?("approval:review")

  class Scope < Scope
    def resolve
      permit?("approval:review") ? scope.all : scope.none
    end
  end
end
