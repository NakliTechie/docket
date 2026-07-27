class WorkCommentPolicy < ApplicationPolicy
  def index?  = permit?("work:read")
  def create? = permit?("work:write")
  # Authors edit their own words; nobody else rewrites them.
  def update?  = permit?("work:write") && record.author_id == user&.id
  def destroy? = permit?("work:write") && record.author_id == user&.id

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.all : scope.none
    end
  end
end
