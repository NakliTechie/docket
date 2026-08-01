module Api
  module V1
    class WorkItemsController < BaseController
      require_feature "work"
      before_action :set_item, only: %i[show update destroy transition]

      def index
        scope = api_scope(WorkItem, scope: "work:read").includes(:workflow_state, :project)
                                                        .search(params[:q])
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
        project = api_scope(Project, scope: "work:write").find(params.require(:work_item)[:project_id])
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
        attributes = item_params.except(:project_id)
        requested_state = requested_workflow_state
        custom_fields = attributes.delete(:custom_fields)
        @item.assign_attributes(attributes)
        @item.assign_custom_fields(custom_fields) if custom_fields
        if @item.save
          moved = requested_state.nil? || requested_state == @item.workflow_state ||
                  @item.guarded_transition_to(requested_state, requested_by: current_user)
          payload = { data: Serialize.work_item(@item.reload) }
          unless moved
            approval = @item.approval_requests.status_pending.recent_first
                            .find_by(requested_action: requested_state.id.to_s)
            payload[:approval_request] = Serialize.approval_request(approval)
          end
          render json: payload, status: (moved ? :ok : :accepted)
        else
          render_validation_errors(@item)
        end
      end

      # The one transition point, same as the console and the board — so an API
      # move is audited and echoes to linked cases exactly like a human's.
      def transition
        authorize_api!(@item, :transition?, scope: "work:write")
        state = @item.project.workflow_states.find(params.require(:workflow_state_id))
        if @item.guarded_transition_to(state, requested_by: current_user)
          render json: { data: Serialize.work_item(@item.reload) }
        else
          approval = @item.approval_requests.status_pending.recent_first
                          .find_by(requested_action: state.id.to_s)
          render json: { data: Serialize.work_item(@item.reload),
                         approval_request: Serialize.approval_request(approval) }, status: :accepted
        end
      end

      def destroy
        authorize_api!(@item, :destroy?, scope: "work:manage")
        @item.destroy
        head :no_content
      end

      private

      def set_item
        required_scope = { "show" => "work:read", "update" => "work:write",
                           "transition" => "work:write", "destroy" => "work:manage" }.fetch(action_name)
        @item = api_scope(WorkItem, scope: required_scope)
                .includes(:project, :workflow_state).find(params[:id])
      end

      def item_params
        permitted = %i[project_id title description kind priority assignee_id
                       workflow_state_id parent_id estimate due_on]
        permitted.delete(:workflow_state_id) if action_name == "update"
        # sprint_id only when the tenant actually has sprints — otherwise a
        # disabled sub-feature stays writable through the item payload.
        permitted << :sprint_id if feature?("work.sprints")
        params.require(:work_item).permit(*permitted, labels: [], custom_fields: {})
      end

      def requested_workflow_state
        state_id = params.dig(:work_item, :workflow_state_id).presence
        return if state_id.blank?

        authorize_api!(@item, :transition?, scope: "work:write")
        @item.project.workflow_states.find(state_id)
      end
    end
  end
end
