class CustomFieldReportPolicy < ApplicationPolicy
  def index?
    case record.to_s
    when "cases" then permit?("case:read")
    when "work_items" then permit?("work:read")
    else false
    end
  end
end
