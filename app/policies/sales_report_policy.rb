# Headless policy for the sales/pipeline report (not backed by one record).
# Visible to all staff, like the deals + pipelines lists it summarizes.
class SalesReportPolicy < ApplicationPolicy
  def index? = staff?
end
