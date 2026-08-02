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
    # This becomes a SELECT id subquery. Strip display ordering: PostgreSQL
    # rejects ORDER BY key on the DISTINCT membership scope when the subquery
    # selects only id (SQLite happened to accept it).
    @open_counts = policy_scope(WorkItem).open.where(project: @projects.reorder(nil)).group(:project_id).count
  end

  def show
    authorize @project
    redirect_to project_board_path(@project)
  end

  def new
    @project = Project.new(lead: Current.user)
    authorize @project
  end

  def create
    @project = Project.new(project_params)
    @project.lead ||= Current.user
    authorize @project
    if @project.save
      redirect_to project_board_path(@project), notice: t(".created", key: @project.key)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
    build_missing_assignment_rules
  end

  def update
    authorize @project
    if @project.update(project_params)
      redirect_to projects_path, notice: t(".updated")
    else
      build_missing_assignment_rules
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
    params.require(:project).permit(:key, :name, :description, :lead_id, :visibility,
                                    member_ids: [],
                                    workflow_states_attributes: %i[id name position wip_limit],
                                    work_assignment_rules_attributes: %i[id work_kind assignee_id _destroy])
  end

  def build_missing_assignment_rules
    existing = @project.work_assignment_rules.map(&:work_kind)
    (WorkItem.kinds.keys - existing).each do |kind|
      @project.work_assignment_rules.build(work_kind: kind)
    end
  end
end
