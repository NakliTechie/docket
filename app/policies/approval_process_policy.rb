# Defining maker-checker rules is cross-module approval governance. Reviewers
# can configure case, Work, and connector gates even when Service Desk is off.
class ApprovalProcessPolicy < ApplicationPolicy
  def index?   = permit?("invocation:review")
  def show?    = permit?("invocation:review")
  def create?  = permit?("invocation:review")
  def update?  = permit?("invocation:review")
  def destroy? = permit?("invocation:review")

  class Scope < Scope
    def resolve
      user&.can?("invocation:review") ? scope.all : scope.none
    end
  end
end
