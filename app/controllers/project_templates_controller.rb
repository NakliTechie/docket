class ProjectTemplatesController < ApplicationController
  require_feature "work"
  before_action :set_template, only: %i[edit update destroy]

  def index
    authorize ProjectTemplate
    @templates = policy_scope(ProjectTemplate).includes(:project_template_items).order(:name)
  end

  def new
    @template = ProjectTemplate.new
    @template.project_template_items.build
    authorize @template
  end

  def create
    @template = ProjectTemplate.new(template_params)
    authorize @template
    if @template.save
      redirect_to project_templates_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @template
    append_blank_item
  end

  def update
    authorize @template
    if @template.update(template_params)
      redirect_to project_templates_path, notice: t(".updated")
    else
      append_blank_item
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @template
    @template.destroy
    redirect_to project_templates_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_template
    @template = policy_scope(ProjectTemplate).find(params[:id])
  end

  def template_params
    params.require(:project_template).permit(
      :name, :key_prefix, :description, :active,
      project_template_items_attributes: %i[id title description kind priority estimate due_offset_days position _destroy]
    )
  end

  def append_blank_item
    @template.project_template_items.build unless @template.project_template_items.any?(&:new_record?)
  end
end
