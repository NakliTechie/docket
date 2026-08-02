# Defining maker-checker rules is cross-module approval governance. Reviewers
# can configure case, Work, and connector gates even when Service Desk is off.
class ApprovalProcessPolicy < ApplicationPolicy
  def index?   = permit?("approval:review")
  def show?    = permit?("approval:review")
  def create?  = permit?("approval:review")
  def update?  = permit?("approval:review")
  def destroy? = permit?("approval:review")

  class Scope < Scope
    def resolve
      user&.can?("approval:review") ? scope.all : scope.none
    end
  end
end
