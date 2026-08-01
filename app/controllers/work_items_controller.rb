# The work item workspace — the Work module's equivalent of the case workspace.
class WorkItemsController < ApplicationController
  require_feature "work"
  before_action :set_project, only: %i[index new create bulk_update]
  before_action :set_item, only: %i[show edit update destroy transition watch]

  def index
    authorize WorkItem
    @saved_views = Current.user.saved_views.for_resource("work_items", context_id: @project.id).order(:name)
    @current_saved_view = @saved_views.find_by(id: params[:saved_view_id])
    raw_filters = @current_saved_view&.filters || params.permit(*SavedView::RESOURCE_FILTERS.fetch("work_items"))
    filters = SavedView.sanitize_filters("work_items", raw_filters).with_indifferent_access
    scope = policy_scope(WorkItem).where(project: @project)
    @has_any_items = scope.exists?
    @items = scope.includes(:assignee, :workflow_state, :sprint).search(filters[:q])
    @items = @items.where(assignee_id: filters[:assignee_id]) if filters[:assignee_id].present?
    @items = @items.where(kind: filters[:kind]) if filters[:kind].present?
    @items = @items.where(workflow_state_id: filters[:state_id]) if filters[:state_id].present?
    @items = @items.open if filters[:open] == "1"
    @filters = ActionController::Parameters.new(filters)
    @pagy, @items = pagy(@items.order(:number))
  end

  def bulk_update
    items = selected_items
    action = params.require(:bulk_action)
    policy_action = action == "transition" ? :transition? : :update?
    items.each { |item| authorize item, policy_action }

    WorkItem.transaction do
      case action
      when "assign" then bulk_assign(items)
      when "transition" then bulk_transition(items)
      when "priority" then bulk_priority(items)
      else raise ActionController::BadRequest, "unsupported bulk action"
      end
    end
    redirect_back fallback_location: project_work_items_path(@project),
                  notice: t("work_items.bulk_update.updated", count: items.size)
  end

  def show
    authorize @item
    @comment = WorkComment.new
    @relation = WorkItemRelation.new(source: @item)
    @relation_targets = policy_scope(WorkItem).where.not(id: @item.id).includes(:project).order(:project_id, :number)
  end

  def new
    @item = @project.work_items.new(kind: params[:kind].presence || :task)
    authorize @item
  end

  def create
    @item = @project.work_items.new(item_params)
    @item.reporter = Current.user
    authorize @item
    if @item.save
      redirect_to work_item_path(@item), notice: t(".created", reference: @item.reference)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @item
  end

  def update
    authorize @item
    attributes = item_params
    requested_state = requested_workflow_state
    custom_fields = attributes.delete(:custom_fields)
    @item.assign_attributes(attributes)
    @item.assign_custom_fields(custom_fields) if custom_fields
    if @item.save
      moved = requested_state.nil? || requested_state == @item.workflow_state ||
              @item.guarded_transition_to(requested_state, requested_by: Current.user)
      key = moved ? ".updated" : "work_items.transition.submitted_for_approval"
      redirect_to work_item_path(@item), notice: t(key, state: requested_state&.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Board moves and the workspace's status control land here — one transition
  # point, so nothing bypasses the audit trail.
  def transition
    authorize @item, :transition?
    state = @item.project.workflow_states.find(params[:workflow_state_id])
    moved = @item.guarded_transition_to(state, requested_by: Current.user)
    respond_to do |format|
      format.html do
        key = moved ? ".moved" : ".submitted_for_approval"
        redirect_back fallback_location: work_item_path(@item), notice: t(key, state: state.name)
      end
      format.json { head(moved ? :no_content : :accepted) }
    end
  end

  def watch
    authorize @item, :watch?
    existing = @item.work_watches.find_by(user: Current.user)
    existing ? existing.destroy : @item.work_watches.create!(user: Current.user)
    redirect_to work_item_path(@item)
  end

  def destroy
    authorize @item
    project = @item.project
    @item.destroy
    redirect_to project_work_items_path(project), notice: t(".deleted")
  end

  private

  def set_project
    @project = policy_scope(Project).find(params[:project_id])
  end

  def set_item
    @item = policy_scope(WorkItem).includes(:project, :work_comments).find(params[:id])
  end

  def item_params
    permitted = %i[title description kind priority assignee_id workflow_state_id
                   parent_id estimate due_on]
    permitted.delete(:workflow_state_id) if action_name == "update"
    # sprint_id only when the tenant actually has sprints — otherwise a disabled
    # sub-feature stays writable through the item form.
    permitted << :sprint_id if feature?("work.sprints")
    params.require(:work_item).permit(*permitted, labels: [], custom_fields: {})
  end

  def requested_workflow_state
    state_id = params.dig(:work_item, :workflow_state_id).presence
    return if state_id.blank?

    authorize @item, :transition?
    @item.project.workflow_states.find(state_id)
  end

  def selected_items
    ids = Array(params[:work_item_ids]).map(&:to_s).uniq
    raise ActionController::BadRequest, "select between 1 and 100 work items" unless ids.size.between?(1, 100)

    records = policy_scope(WorkItem).where(project: @project, id: ids).to_a
    raise ActiveRecord::RecordNotFound unless records.size == ids.size

    records
  end

  def bulk_assign(items)
    assignee_id = params[:assignee_id].presence
    assignee = assignee_id && User.active.staff.find_by(id: assignee_id)
    raise ActionController::BadRequest, "invalid assignee" if assignee_id && assignee.nil?

    items.each { |item| item.update!(assignee: assignee) }
  end

  def bulk_transition(items)
    state = @project.workflow_states.find(params.require(:workflow_state_id))
    items.each { |item| item.guarded_transition_to(state, requested_by: Current.user) }
  end

  def bulk_priority(items)
    priority = params.require(:priority).to_s
    raise ActionController::BadRequest, "invalid priority" unless WorkItem.priorities.key?(priority)

    items.each { |item| item.update!(priority: priority) }
  end
end
