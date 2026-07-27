# The work item workspace — the Work module's equivalent of the case workspace.
class WorkItemsController < ApplicationController
  require_feature "work"
  before_action :set_project, only: %i[index new create]
  before_action :set_item, only: %i[show edit update destroy transition watch]

  def index
    authorize WorkItem
    @items = policy_scope(WorkItem).where(project: @project)
               .includes(:assignee, :workflow_state, :sprint)
    @items = @items.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    @items = @items.where(kind: params[:kind]) if params[:kind].present?
    @items = @items.where(workflow_state_id: params[:state_id]) if params[:state_id].present?
    @items = @items.open if params[:open] == "1"
    @pagy, @items = pagy(@items.order(:number))
  end

  def show
    authorize @item
    @comment = WorkComment.new
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
    if @item.update(item_params)
      redirect_to work_item_path(@item), notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Board moves and the workspace's status control land here — one transition
  # point, so nothing bypasses the audit trail.
  def transition
    authorize @item, :transition?
    state = @item.project.workflow_states.find(params[:workflow_state_id])
    @item.transition_to!(state)
    respond_to do |format|
      format.html { redirect_back fallback_location: work_item_path(@item), notice: t(".moved", state: state.name) }
      format.json { head :no_content }
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
    params.require(:work_item).permit(:title, :description, :kind, :priority, :assignee_id,
                                      :workflow_state_id, :parent_id, :sprint_id, :estimate,
                                      :due_on, label_list: [])
  end
end
