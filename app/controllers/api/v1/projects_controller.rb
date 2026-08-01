module Api
  module V1
    class ProjectsController < BaseController
      require_feature "work"
      before_action :set_project, only: %i[show update destroy]

      def index
        scope = api_scope(Project, scope: "work:read").includes(:project_memberships)
        scope = scope.active unless params[:archived] == "1"
        pagy, records = pagy(scope.order(:key))
        render json: { data: records.map { |p| Serialize.project(p) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@project, :show?, scope: "work:read")
        render json: { data: Serialize.project(@project),
                       workflow_states: @project.workflow_states.ordered.map { |s|
                         { id: s.id, name: s.name, category: s.category, position: s.position }
                       } }
      end

      def create
        authorize_api!(Project.new, :create?, scope: "work:manage")
        project = Project.new(project_params)
        if project.save
          render json: { data: Serialize.project(project) }, status: :created
        else
          render_validation_errors(project)
        end
      end

      def update
        authorize_api!(@project, :update?, scope: "work:manage")
        if @project.update(project_params)
          render json: { data: Serialize.project(@project) }
        else
          render_validation_errors(@project)
        end
      end

      def destroy
        authorize_api!(@project, :destroy?, scope: "work:manage")
        @project.destroy
        head :no_content
      end

      private

      def set_project
        required_scope = action_name == "show" ? "work:read" : "work:manage"
        @project = api_scope(Project, scope: required_scope).find(params[:id])
      end

      def project_params
        params.require(:project).permit(
          :key, :name, :description, :lead_id, :visibility, member_ids: [],
          work_assignment_rules_attributes: %i[id work_kind assignee_id _destroy]
        )
      end
    end
  end
end
