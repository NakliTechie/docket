class WorkCommentPolicy < ApplicationPolicy
  def index?  = permit?("work:read") && readable_item?
  def create? = permit?("work:write") && writable_item?
  # Authors edit their own words; nobody else rewrites them.
  def update?  = permit?("work:write") && writable_item? && record.author_type == "User" && record.author_id == user&.id
  def destroy? = update?

  private

  def project_visible? = record.is_a?(Class) || record.work_item&.project&.visible_to?(user) || false

  def readable_item? = project_visible? && (record.is_a?(Class) || WorkItemPolicy.new(user, record.work_item).show?)
  def writable_item? = project_visible? && (record.is_a?(Class) || WorkItemPolicy.new(user, record.work_item).update?)

  class Scope < Scope
    def resolve
      return scope.none unless permit?("work:read")

      visible_items = RecordVisibility.resolve(user, WorkItem.visible_to(user), access: :read)
      scope.where(work_item_id: visible_items.select(:id))
    end
  end
end
