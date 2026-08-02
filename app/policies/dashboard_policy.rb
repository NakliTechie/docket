# Headless policy for the operational dashboard (not backed by one record).
# The effector-governance plane (who-approved-what, autonomy ratio) is
# sensitive, so visibility tracks report:operational rather than all staff
# (unlike SalesReportPolicy).
class DashboardPolicy < ApplicationPolicy
  def index? = permit?("report:operational")
  def export? = index? && permit?("report:export")
end
