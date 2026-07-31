module Api
  module V1
    class BusinessCalendarsController < BaseController
      require_feature "service_desk"
      before_action :set_calendar, only: %i[show update destroy]

      def index
        records = api_scope(BusinessCalendar, scope: "config:read")
          .includes(:business_calendar_windows, :business_calendar_exceptions).order(:name)
        render json: { data: records.map { |calendar| Serialize.business_calendar(calendar) } }
      end

      def show
        authorize_api!(@calendar, :show?, scope: "config:read")
        render json: { data: Serialize.business_calendar(@calendar) }
      end

      def create
        authorize_api!(BusinessCalendar.new, :create?, scope: "config:write")
        calendar = BusinessCalendar.new(calendar_params)
        if calendar.save
          render json: { data: Serialize.business_calendar(calendar) }, status: :created
        else
          render_validation_errors(calendar)
        end
      end

      def update
        authorize_api!(@calendar, :update?, scope: "config:write")
        if @calendar.update(calendar_params)
          render json: { data: Serialize.business_calendar(@calendar.reload) }
        else
          render_validation_errors(@calendar)
        end
      end

      def destroy
        authorize_api!(@calendar, :destroy?, scope: "config:write")
        if @calendar.destroy
          head :no_content
        else
          render_validation_errors(@calendar)
        end
      end

      private

      def set_calendar
        @calendar = BusinessCalendar.find(params[:id])
      end

      def calendar_params
        params.require(:business_calendar).permit(
          :name, :time_zone, :is_default,
          business_calendar_windows_attributes: %i[id weekday starts_at ends_at _destroy],
          business_calendar_exceptions_attributes: %i[id on_date name closed starts_at ends_at _destroy]
        )
      end
    end
  end
end
