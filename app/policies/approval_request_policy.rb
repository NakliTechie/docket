# Acting on a maker-checker request is the human-of-record activity — same tier
# as the decision-appeal queue and effector approvals (invocation:review).
class ApprovalRequestPolicy < ApplicationPolicy
  def index?   = permit?("invocation:review")
  def approve? = permit?("invocation:review")
  def reject?  = permit?("invocation:review")

  class Scope < Scope
    def resolve
      permit?("invocation:review") ? scope.all : scope.none
    end
  end
end
