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

      def report
        project = api_scope(Project, scope: "work:read").find(params[:project_id])
        authorize_api!(project, :show?, scope: "work:read")
        render json: { data: Sprints::Velocity.call(project: project).merge(project_id: project.id) }
      end

      def create
        project = api_scope(Project, scope: "work:write").find(params.require(:sprint)[:project_id])
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
      rescue ArgumentError => e
        render_error("invalid_closeout", detail: e.message, status: :unprocessable_entity)
      end

      private

      def set_sprint
        required_scope = action_name == "show" ? "work:read" : "work:write"
        @sprint = api_scope(Sprint, scope: required_scope).find(params[:id])
      end

      def sprint_params
        # :status is deliberately NOT permitted. Closing must go through
        # Sprints::Closeout, which decides what happens to unfinished work;
        # setting it here would strand items in a closed sprint and falsify
        # every velocity number computed from it. Use POST /sprints/:id/close.
        params.require(:sprint).permit(:project_id, :name, :goal, :starts_on, :ends_on)
      end
    end
  end
end
