# Operator landing dashboard — the case-desk, sales, connector-ingestion and
# effector-accountability planes on one page, composed by DashboardOverview.
# Admin/supervisor only (DashboardPolicy). Computed from this deployment's own
# data; never transmitted anywhere.
class DashboardsController < ApplicationController
  def index
    authorize :dashboard, policy_class: DashboardPolicy
    setup = SetupProgress.new(actor: Current.user, base_url: request.base_url)
    if request.format.html? &&
        PlatformAreaPolicy.new(Current.user, :settings).show? &&
        setup.fresh_tenant?
      return redirect_to setup_path
    end

    @from = parse_date(params[:from]) || 30.days.ago.to_date
    @to = parse_date(params[:to]) || Date.current
    @overview = DashboardOverview.new(from: @from, to: @to)

    respond_to do |format|
      format.html
      format.csv do
        authorize :dashboard, :export?, policy_class: DashboardPolicy
        send_data @overview.to_csv, filename: "docket-dashboard-#{@from}-#{@to}.csv"
      end
    end
  rescue ArgumentError => e
    redirect_to dashboard_path, alert: e.message
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
