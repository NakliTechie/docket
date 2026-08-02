# Reviewing decision appeals is the human-of-record activity — same tier as the
# the decisioning controls and the effector approval queue.
class DecisionAppealPolicy < ApplicationPolicy
  def index?    = permit?("appeal:adjudicate")
  def create?   = permit?("appeal:adjudicate")
  def overturn? = permit?("appeal:adjudicate")
  def deny?     = permit?("appeal:adjudicate")

  class Scope < Scope
    def resolve
      permit?("appeal:adjudicate") ? scope.all : scope.none
    end
  end
end
