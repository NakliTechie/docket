class LeadPolicy < ApplicationPolicy
  def index?   = permit?("lead:read")
  def show?    = permit?("lead:read") && record_in_scope?(:read)
  def create?  = permit?("lead:write")
  def update?  = permit?("lead:write") && record_in_scope?(:write)
  def convert? = update?
  def mark_unqualified? = update?
  def merge?   = update? && permit?("lead:delete")
  def destroy? = permit?("lead:delete") && record_in_scope?(:write)

  class Scope < Scope
    def resolve
      permit?("lead:read") ? record_scope : scope.none
    end
  end
end
