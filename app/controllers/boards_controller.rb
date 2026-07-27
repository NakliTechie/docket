# The kanban view of a project: one column per workflow state. Moving an item
# is a normal transition, so it audits exactly like every other status change.
class BoardsController < ApplicationController
  require_feature "work"

  # Enough to work from; not enough to melt the page. The backlog list is the
  # unbounded (paginated) view.
  COLUMN_LIMIT = 50
  before_action :set_project

  def show
    authorize @project, :show?
    @states = @project.workflow_states.ordered
    scope = policy_scope(WorkItem).where(project: @project)
             # :project because WorkItem#reference reads project.key on every card.
             .includes(:assignee, :workflow_state, :project)
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    # The active sprint scopes the board when one is running; ?sprint=all opts
    # out. Gated: with work.sprints off the board must neither name a sprint nor
    # be silently filtered down to one.
    if feature?("work.sprints") && params[:sprint] != "all"
      @sprint = @project.sprints.find_by(status: :active)
    end
    scope = scope.where(sprint: @sprint) if @sprint

    # Per-column cap. This used to load EVERY work item in the project and group
    # them in Ruby — fine on a demo, a cliff on a real backlog of tens of
    # thousands. A kanban board is a working surface, not an archive: past a
    # screenful nobody reads it, and the backlog list (which paginates) is where
    # you go to see everything.
    @column_limit = COLUMN_LIMIT
    @totals_by_state = scope.reorder(nil).group(:workflow_state_id).count
    @items_by_state = @project.workflow_states.ordered.each_with_object({}) do |state, acc|
      acc[state.id] = scope.where(workflow_state_id: state.id)
                           .order(:position, :number)
                           .limit(COLUMN_LIMIT)
                           .to_a
    end
  end

  private

  def set_project
    @project = policy_scope(Project).find(params[:project_id])
  end
end
