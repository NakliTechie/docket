# Defining maker-checker rules is desk configuration — gated case_config:manage,
# like queues / categories / routing rules.
class ApprovalProcessPolicy < ApplicationPolicy
  def index?   = permit?("case_config:manage")
  def show?    = permit?("case_config:manage")
  def create?  = permit?("case_config:manage")
  def update?  = permit?("case_config:manage")
  def destroy? = permit?("case_config:manage")

  class Scope < Scope
    def resolve
      user&.can?("case_config:manage") ? scope.all : scope.none
    end
  end
end
