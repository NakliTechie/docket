# Reviewing decision appeals is the human-of-record activity — same tier as the
# the decisioning controls and the effector approval queue.
class DecisionAppealPolicy < ApplicationPolicy
  def index?    = permit?("appeal:adjudicate")
  def create?   = permit?("appeal:adjudicate")
  def overturn?
    permit?("appeal:adjudicate") &&
      RecordVisibility.allowed?(user, record.decision, access: :write)
  end
  def deny? = overturn?

  class Scope < Scope
    def resolve
      return scope.none unless permit?("appeal:adjudicate")

      visible = RecordVisibility.resolve(user, Decision.all, access: :read)
      scope.where(decision_id: visible.select(:id))
    end
  end
end
