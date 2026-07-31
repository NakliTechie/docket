class CustomFieldDefinitionsController < ApplicationController
  before_action :set_definition, only: %i[edit update]

  def index
    authorize CustomFieldDefinition
    @resource_type = normalized_resource_type
    @definitions = policy_scope(CustomFieldDefinition).for_resource(@resource_type).ordered
  end

  def new
    @definition = CustomFieldDefinition.new(resource_type: normalized_resource_type)
    authorize @definition
  end

  def create
    @definition = CustomFieldDefinition.new(definition_params)
    assign_options(@definition)
    authorize @definition
    if @definition.save
      redirect_to custom_fields_path(resource_type: @definition.resource_type), notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @definition
  end

  def update
    authorize @definition
    @definition.assign_attributes(definition_params.except(:resource_type, :key))
    assign_options(@definition)
    if @definition.save
      redirect_to custom_fields_path(resource_type: @definition.resource_type), notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_definition
    @definition = policy_scope(CustomFieldDefinition).find(params[:id])
  end

  def normalized_resource_type
    value = params[:resource_type].presence || "cases"
    return value if CustomFieldDefinition::RESOURCE_TYPES.include?(value)

    raise ActionController::BadRequest, "unsupported custom-field resource"
  end

  def definition_params
    params.require(:custom_field_definition).permit(
      :resource_type, :key, :label, :field_type, :required, :active, :reportable, :position
    )
  end

  def assign_options(definition)
    definition.options = params.dig(:custom_field_definition, :options_text).to_s.lines.map(&:strip)
  end
end
