# The kanban view of a project: one column per workflow state. Moving an item
# is a normal transition, so it audits exactly like every other status change.
class BoardsController < ApplicationController
  require_feature "work"
  before_action :set_project

  def show
    authorize @project, :show?
    @states = @project.workflow_states.ordered
    scope = policy_scope(WorkItem).where(project: @project)
             .includes(:assignee, :workflow_state)
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    # The active sprint scopes the board when one is running; ?sprint=all opts
    # out. Gated: with work.sprints off the board must neither name a sprint nor
    # be silently filtered down to one.
    if feature?("work.sprints") && params[:sprint] != "all"
      @sprint = @project.sprints.find_by(status: :active)
    end
    scope = scope.where(sprint: @sprint) if @sprint
    @items_by_state = scope.order(:position, :number).group_by(&:workflow_state_id)
  end

  private

  def set_project
    @project = policy_scope(Project).find(params[:project_id])
  end
end
