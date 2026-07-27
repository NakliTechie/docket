module Api
  module V1
    class WorkItemsController < BaseController
      require_feature "work"
      before_action :set_item, only: %i[show update destroy transition]

      def index
        scope = api_scope(WorkItem, scope: "work:read").includes(:workflow_state, :project)
        scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
        scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
        scope = scope.where(sprint_id: params[:sprint_id]) if params[:sprint_id].present?
        scope = scope.open if params[:open] == "1"
        pagy, records = pagy(scope.order(:project_id, :number))
        render json: { data: records.map { |i| Serialize.work_item(i) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@item, :show?, scope: "work:read")
        render json: { data: Serialize.work_item(@item),
                       comments: @item.work_comments.map { |c| Serialize.work_comment(c) } }
      end

      def create
        project = Project.find(params.require(:work_item)[:project_id])
        item = project.work_items.new(item_params.except(:project_id))
        item.reporter ||= current_user
        authorize_api!(item, :create?, scope: "work:write")
        if item.save
          render json: { data: Serialize.work_item(item) }, status: :created
        else
          render_validation_errors(item)
        end
      end

      def update
        authorize_api!(@item, :update?, scope: "work:write")
        if @item.update(item_params.except(:project_id))
          render json: { data: Serialize.work_item(@item) }
        else
          render_validation_errors(@item)
        end
      end

      # The one transition point, same as the console and the board — so an API
      # move is audited and echoes to linked cases exactly like a human's.
      def transition
        authorize_api!(@item, :transition?, scope: "work:write")
        state = @item.project.workflow_states.find(params.require(:workflow_state_id))
        @item.transition_to!(state)
        render json: { data: Serialize.work_item(@item.reload) }
      end

      def destroy
        authorize_api!(@item, :destroy?, scope: "work:write")
        @item.destroy
        head :no_content
      end

      private

      def set_item
        @item = WorkItem.includes(:project, :workflow_state).find(params[:id])
      end

      def item_params
        params.require(:work_item).permit(:project_id, :title, :description, :kind, :priority,
                                          :assignee_id, :workflow_state_id, :parent_id,
                                          :sprint_id, :estimate, :due_on, labels: [])
      end
    end
  end
end
