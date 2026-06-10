module Admin
  # Activity & Usage (handoff §6): the deployment owner's own
  # "who's doing what", served entirely from the local audit log and
  # sessions — never transmitted anywhere.
  class ActivityController < ApplicationController
    def index
      authorize :activity, policy_class: AdminAreaPolicy
      @from = parse_date(params[:from]) || 30.days.ago.to_date
      @to = parse_date(params[:to]) || Date.current
      @report = ActivityReport.new(from: @from, to: @to)

      respond_to do |format|
        format.html
        format.csv { send_data @report.to_csv, filename: "docket-activity-#{@from}-#{@to}.csv" }
      end
    end

    private

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
