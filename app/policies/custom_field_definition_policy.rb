class CustomFieldDefinitionPolicy < ApplicationPolicy
  def index? = case_manager? || work_manager?
  def show? = manage_resource?
  def create? = manage_resource?
  def update? = manage_resource?

  class Scope < Scope
    def resolve
      resources = []
      resources << "cases" if user&.can?("queue:manage")
      resources << "work_items" if user&.can?("project:manage")
      scope.where(resource_type: resources)
    end
  end

  private

  def manage_resource?
    case record.resource_type
    when "cases" then case_manager?
    when "work_items" then work_manager?
    else false
    end
  end

  def case_manager? = permit?("queue:manage")
  def work_manager? = permit?("project:manage")
end
