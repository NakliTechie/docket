# Sprint planning and close-out. Running a cadence is work:write, not
# project:manage — a team lead runs their own sprints without workspace-admin
# rights (see SprintPolicy).
class SprintsController < ApplicationController
  require_feature "work.sprints"
  before_action :set_project
  before_action :set_sprint, only: %i[edit update start close destroy]

  def index
    authorize Sprint
    @sprints = policy_scope(Sprint).where(project: @project).ordered
    @counts = WorkItem.where(sprint: @sprints).group(:sprint_id).count
    @backlog_count = policy_scope(WorkItem).where(project: @project, sprint: nil).open.count
    @report = Sprints::Velocity.call(project: @project)
  end

  def new
    @sprint = @project.sprints.new
    authorize @sprint
  end

  def create
    @sprint = @project.sprints.new(sprint_params)
    authorize @sprint
    if @sprint.save
      redirect_to project_sprints_path(@project), notice: t(".created", name: @sprint.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @sprint
  end

  def update
    authorize @sprint
    if @sprint.update(sprint_params)
      redirect_to project_sprints_path(@project), notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def start
    authorize @sprint, :start?
    if @sprint.update(status: :active)
      redirect_to project_board_path(@project), notice: t(".started", name: @sprint.name)
    else
      redirect_to project_sprints_path(@project),
                  alert: @sprint.errors.full_messages.to_sentence
    end
  end

  # Closing must decide what happens to work that didn't finish. Default is the
  # backlog; the alternative is an explicit roll-forward to a named sprint. We
  # never silently close over unfinished work.
  def close
    authorize @sprint, :close?
    target = params[:roll_to].presence && @project.sprints.find_by(id: params[:roll_to])
    moved = Sprints::Closeout.call(sprint: @sprint, roll_to: target)
    redirect_to project_sprints_path(@project),
                notice: t(".closed", name: @sprint.name, count: moved,
                          destination: target&.name || t(".backlog"))
  rescue ArgumentError => e
    # Closeout refuses the nonsense cases (rolling into itself, into another
    # project, into a closed sprint, re-closing). Say so rather than 500.
    redirect_to project_sprints_path(@project), alert: e.message
  end

  def destroy
    authorize @sprint
    @sprint.destroy
    redirect_to project_sprints_path(@project), notice: t(".deleted")
  end

  private

  def set_project
    @project = policy_scope(Project).find(params[:project_id])
  end

  def set_sprint
    @sprint = policy_scope(Sprint).where(project: @project).find(params[:id])
  end

  def sprint_params
    params.require(:sprint).permit(:name, :goal, :starts_on, :ends_on)
  end
end
