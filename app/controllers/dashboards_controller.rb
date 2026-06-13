# Operator landing dashboard — the case-desk, sales, connector-ingestion and
# effector-accountability planes on one page, composed by DashboardOverview.
# Admin/supervisor only (DashboardPolicy). Computed from this deployment's own
# data; never transmitted anywhere.
class DashboardsController < ApplicationController
  def index
    authorize :dashboard, policy_class: DashboardPolicy
    @from = parse_date(params[:from]) || 30.days.ago.to_date
    @to = parse_date(params[:to]) || Date.current
    @overview = DashboardOverview.new(from: @from, to: @to)

    respond_to do |format|
      format.html
      format.csv { send_data @overview.to_csv, filename: "docket-dashboard-#{@from}-#{@to}.csv" }
    end
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
