# Routing rules are pure desk configuration — the whole surface (including
# reading the list) is gated on routing-management authority.
class RoutingRulePolicy < ApplicationPolicy
  def index?   = permit?("routing:manage")
  def show?    = permit?("routing:manage")
  def create?  = permit?("routing:manage")
  def update?  = permit?("routing:manage")
  def destroy? = permit?("routing:manage")
  def move?    = permit?("routing:manage")

  class Scope < Scope
    def resolve
      user&.can?("routing:manage") ? scope.all : scope.none
    end
  end
end
