# Sales & pipeline analytics (v1.2 CRM): value by stage, win/loss, lead
# conversion — the counterpart to Admin::ActivityController for the sales
# side, computed from this deployment's own deal + lead data.
class SalesReportsController < ApplicationController
  def index
    authorize :sales_report, policy_class: SalesReportPolicy
    @from = parse_date(params[:from]) || 30.days.ago.to_date
    @to = parse_date(params[:to]) || Date.current
    @report = SalesReport.new(from: @from, to: @to)

    respond_to do |format|
      format.html
      format.csv { send_data @report.to_csv, filename: "docket-sales-#{@from}-#{@to}.csv" }
    end
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
