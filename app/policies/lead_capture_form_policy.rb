class LeadCaptureFormPolicy < ApplicationPolicy
  def index?   = permit?("lead:write")
  def show?    = permit?("lead:write")
  def create?  = permit?("lead:write")
  def update?  = permit?("lead:write")
  def destroy? = permit?("lead:write")

  class Scope < Scope
    def resolve
      permit?("lead:write") ? scope.all : scope.none
    end
  end
end
