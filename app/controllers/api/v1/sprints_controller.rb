module Api
  module V1
    class SprintsController < BaseController
      require_feature "work.sprints"
      before_action :set_sprint, only: %i[show update close]

      def index
        scope = api_scope(Sprint, scope: "work:read")
        scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
        pagy, records = pagy(scope.ordered)
        render json: { data: records.map { |s| Serialize.sprint(s) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@sprint, :show?, scope: "work:read")
        render json: { data: Serialize.sprint(@sprint) }
      end

      def create
        project = Project.find(params.require(:sprint)[:project_id])
        sprint = project.sprints.new(sprint_params.except(:project_id))
        authorize_api!(sprint, :create?, scope: "work:write")
        if sprint.save
          render json: { data: Serialize.sprint(sprint) }, status: :created
        else
          render_validation_errors(sprint)
        end
      end

      def update
        authorize_api!(@sprint, :update?, scope: "work:write")
        if @sprint.update(sprint_params.except(:project_id))
          render json: { data: Serialize.sprint(@sprint) }
        else
          render_validation_errors(@sprint)
        end
      end

      def close
        authorize_api!(@sprint, :close?, scope: "work:write")
        target = params[:roll_to].presence && @sprint.project.sprints.find_by(id: params[:roll_to])
        moved = Sprints::Closeout.call(sprint: @sprint, roll_to: target)
        render json: { data: Serialize.sprint(@sprint.reload), moved_items: moved }
      end

      private

      def set_sprint
        @sprint = Sprint.find(params[:id])
      end

      def sprint_params
        params.require(:sprint).permit(:project_id, :name, :goal, :status, :starts_on, :ends_on)
      end
    end
  end
end
