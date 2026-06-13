# Routing rules are pure desk configuration — the whole surface (including
# reading the list) is gated on case_config:manage, the same authority that
# governs queues/categories/SLAs.
class RoutingRulePolicy < ApplicationPolicy
  def index?   = permit?("case_config:manage")
  def show?    = permit?("case_config:manage")
  def create?  = permit?("case_config:manage")
  def update?  = permit?("case_config:manage")
  def destroy? = permit?("case_config:manage")
  def move?    = permit?("case_config:manage")

  class Scope < Scope
    def resolve
      user&.can?("case_config:manage") ? scope.all : scope.none
    end
  end
end
