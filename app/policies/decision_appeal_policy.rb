# Reviewing decision appeals is the human-of-record activity — same tier as the
# decisioning controls and the effector approval queue (invocation:review).
class DecisionAppealPolicy < ApplicationPolicy
  def index?    = permit?("invocation:review")
  def create?   = permit?("invocation:review")
  def overturn? = permit?("invocation:review")
  def deny?     = permit?("invocation:review")

  class Scope < Scope
    def resolve
      permit?("invocation:review") ? scope.all : scope.none
    end
  end
end
