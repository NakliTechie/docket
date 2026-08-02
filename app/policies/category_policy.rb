class CategoryPolicy < ApplicationPolicy
  def index?   = permit?("case:read")
  def show?    = permit?("case:read")
  def create?  = permit?("queue:manage")
  def update?  = permit?("queue:manage")
  def destroy? = permit?("queue:manage")

  # Granting the AI autonomous resolution is a platform-tier trust decision.
  def toggle_auto_resolve? = permit?("ai:autonomy")

  class Scope < Scope
    def resolve
      permit?("case:read") ? scope.all : scope.none
    end
  end
end
