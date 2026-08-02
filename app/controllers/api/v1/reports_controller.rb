module Api
  module V1
    # API parity for the Activity & Usage view (handoff §12).
    class ReportsController < BaseController
      # The activity report IS case-desk data (cases created/resolved, SLA
      # breaches, volume by queue with queue names). Its access gate is
      # audit:read, which no module owns, so without this a tenant that never
      # bought the desk could read its whole shape through the API.
      require_feature "service_desk", except: :sales
      require_feature "crm", only: :sales

      def activity
        require_report_access!
        from = parse_date(params[:from]) || 30.days.ago.to_date
        to = parse_date(params[:to]) || Date.current
        cases = report_case_scope
        render json: {
          data: ActivityReport.new(
            from: from,
            to: to,
            viewer: current_user,
            case_scope: cases,
            message_scope: Message.with_deleted.where(case_id: cases.select(:id))
          ).as_json
        }
      end

      def csat
        require_report_access!
        from = parse_date(params[:from]) || 30.days.ago.to_date
        to = parse_date(params[:to]) || Date.current
        render json: { data: CsatReport.new(from: from, to: to, case_scope: report_case_scope).as_json }
      end

      def sales
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.can?("report:sales")
        elsif !current_access_token.scope?("crm:read")
          raise ScopeDenied, "crm:read"
        end
        from = parse_date(params[:from]) || 30.days.ago.to_date
        to = parse_date(params[:to]) || Date.current
        render json: {
          data: SalesReport.new(
            from: from,
            to: to,
            deal_scope: report_record_scope(Deal),
            lead_scope: report_record_scope(Lead)
          ).as_json
        }
      end

      private

      def require_report_access!
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.can?("audit:read")
        else
          raise ScopeDenied, "audit:read" unless current_access_token.scope?("audit:read")
        end
      end

      def report_case_scope
        report_record_scope(Case)
      end

      def report_record_scope(model)
        base = model.respond_to?(:with_deleted) ? model.with_deleted : model.all
        current_user ? RecordVisibility.resolve(current_user, base) : base
      end

      def parse_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
