class CustomFieldDefinitionPolicy < ApplicationPolicy
  def index? = CustomFieldDefinition::MANAGE_PERMISSIONS.values.any? { |permission| permit?(permission) }
  def show? = manage_resource?
  def create? = manage_resource?
  def update? = manage_resource?

  class Scope < Scope
    def resolve
      resources = CustomFieldDefinition::RESOURCE_TYPES.select do |resource_type|
        user&.can?(CustomFieldDefinition.manage_permission_for(resource_type))
      end
      scope.where(resource_type: resources)
    end
  end

  private

  def manage_resource?
    permit?(CustomFieldDefinition.manage_permission_for(record.resource_type))
  rescue KeyError
    false
  end
end
