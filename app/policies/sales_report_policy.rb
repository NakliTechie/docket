# Headless policy for the sales/pipeline report (not backed by one record).
# Visible to anyone holding report:sales, like the deals + pipelines it
# summarizes.
class SalesReportPolicy < ApplicationPolicy
  def index? = permit?("report:sales")
end
