class CategoryPolicy < ApplicationPolicy
  def index?   = permit?("case:read")
  def show?    = permit?("case:read")
  def create?  = permit?("case_config:manage")
  def update?  = permit?("case_config:manage")
  def destroy? = permit?("case_config:manage")

  # Granting the AI autonomous resolution is a platform-tier trust decision.
  def toggle_auto_resolve? = permit?("ai:autonomy")

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
