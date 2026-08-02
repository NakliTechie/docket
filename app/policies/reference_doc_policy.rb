class ReferenceDocPolicy < ApplicationPolicy
  def index?   = permit?("knowledge:read")
  def show?    = permit?("knowledge:read")
  def create?  = permit?("knowledge:draft")
  def update?  = permit?("knowledge:draft")
  def review?  = permit?("knowledge:review")
  def publish? = permit?("knowledge:publish")
  def destroy? = permit?("knowledge:admin")
  def retire?  = permit?("knowledge:admin")

  class Scope < Scope
    def resolve
      permit?("knowledge:read") ? scope.all : scope.none
    end
  end
end
