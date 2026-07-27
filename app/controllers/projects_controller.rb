# The Work module's workspace list. Everything under it (board, backlog, items)
# hangs off a project, so this is where the `work` entitlement is enforced for
# the whole module.
class ProjectsController < ApplicationController
  require_feature "work"
  before_action :set_project, only: %i[show edit update destroy archive]

  def index
    authorize Project
    @projects = policy_scope(Project).includes(:lead).order(:key)
    @projects = @projects.active unless params[:archived] == "1"
    @open_counts = WorkItem.open.where(project: @projects).group(:project_id).count
  end

  def show
    authorize @project
    redirect_to project_board_path(@project)
  end

  def new
    @project = Project.new
    authorize @project
  end

  def create
    @project = Project.new(project_params)
    authorize @project
    if @project.save
      redirect_to project_board_path(@project), notice: t(".created", key: @project.key)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
  end

  def update
    authorize @project
    if @project.update(project_params)
      redirect_to projects_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    authorize @project
    @project.update!(archived: !@project.archived)
    redirect_to projects_path,
                notice: t(@project.archived? ? ".archived" : ".unarchived", key: @project.key)
  end

  def destroy
    authorize @project
    @project.destroy
    redirect_to projects_path, notice: t(".deleted")
  end

  private

  def set_project
    @project = policy_scope(Project).find(params[:id])
  end

  def project_params
    params.require(:project).permit(:key, :name, :description, :lead_id,
                                    workflow_states_attributes: %i[id name position wip_limit])
  end
end
