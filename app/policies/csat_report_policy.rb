class CsatReportPolicy < ApplicationPolicy
  def index? = permit?("report:operational")
end
