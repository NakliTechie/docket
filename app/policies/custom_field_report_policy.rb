class CustomFieldReportPolicy < ApplicationPolicy
  def index?
    permit?(CustomFieldDefinition.read_permission_for(record))
  rescue KeyError
    false
  end

  def export? = index? && permit?("report:export")
end
