module Api
  module V1
    class ActivitiesController < BaseController
      require_feature "crm"
      before_action :set_activity, only: %i[show update destroy complete]

      def index
        scope = api_scope(Activity, scope: "crm:read")
        if params[:subject_id].present? && params[:subject_type].present?
          scope = scope.where(subject_type: params[:subject_type], subject_id: params[:subject_id])
        end
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
        pagy, records = pagy(scope.recent_first)
        render json: { data: records.map { |a| Serialize.activity(a) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@activity, :show?, scope: "crm:read")
        render json: { data: Serialize.activity(@activity) }
      end

      def create
        authorize_api!(Activity.new, :create?, scope: "crm:write")
        activity = Activity.new(activity_params)
        if activity.save
          render json: { data: Serialize.activity(activity) }, status: :created
        else
          render_validation_errors(activity)
        end
      end

      def update
        authorize_api!(@activity, :update?, scope: "crm:write")
        if @activity.update(activity_params)
          render json: { data: Serialize.activity(@activity) }
        else
          render_validation_errors(@activity)
        end
      end

      def complete
        authorize_api!(@activity, :complete?, scope: "crm:write")
        @activity.complete!
        render json: { data: Serialize.activity(@activity) }
      end

      def destroy
        authorize_api!(@activity, :destroy?, scope: "crm:write")
        @activity.destroy
        head :no_content
      end

      private

      def set_activity
        @activity = Activity.find(params[:id])
      end

      def activity_params
        params.require(:activity).permit(:kind, :title, :body, :due_at, :owner_id,
                                         :subject_type, :subject_id, :status)
      end
    end
  end
end
