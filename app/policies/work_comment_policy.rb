class WorkCommentPolicy < ApplicationPolicy
  def index?  = permit?("work:read") && project_visible?
  def create? = permit?("work:write") && project_visible?
  # Authors edit their own words; nobody else rewrites them.
  def update?  = permit?("work:write") && project_visible? && record.author_type == "User" && record.author_id == user&.id
  def destroy? = permit?("work:write") && project_visible? && record.author_type == "User" && record.author_id == user&.id

  private

  def project_visible? = record.is_a?(Class) || record.work_item&.project&.visible_to?(user) || false

  class Scope < Scope
    def resolve
      permit?("work:read") ? scope.visible_to(user) : scope.none
    end
  end
end
