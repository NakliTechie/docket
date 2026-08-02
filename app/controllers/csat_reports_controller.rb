class CsatReportsController < ApplicationController
  require_feature "service_desk"

  def index
    authorize :csat_report, policy_class: CsatReportPolicy
    @from = parse_date(params[:from]) || 30.days.ago.to_date
    @to = parse_date(params[:to]) || Date.current
    @report = CsatReport.new(
      from: @from,
      to: @to,
      case_scope: RecordVisibility.resolve(Current.user, Case.with_deleted)
    )

    respond_to do |format|
      format.html
      format.csv do
        authorize :csat_report, :export?, policy_class: CsatReportPolicy
        send_data @report.to_csv, filename: "docket-csat-#{@from}-#{@to}.csv"
      end
    end
  end

  private

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
