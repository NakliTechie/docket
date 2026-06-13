module Api
  module V1
    # API parity for the Activity & Usage view (handoff §12).
    class ReportsController < BaseController
      def activity
        require_report_access!
        from = parse_date(params[:from]) || 30.days.ago.to_date
        to = parse_date(params[:to]) || Date.current
        render json: { data: ActivityReport.new(from: from, to: to, viewer: current_user).as_json }
      end

      private

      def require_report_access!
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.can?("audit:read")
        else
          raise ScopeDenied, "audit:read" unless current_access_token.scope?("audit:read")
        end
      end

      def parse_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
