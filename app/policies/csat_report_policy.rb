class CsatReportPolicy < ApplicationPolicy
  def index? = permit?("report:operational")
  def export? = index? && permit?("report:export")
end
