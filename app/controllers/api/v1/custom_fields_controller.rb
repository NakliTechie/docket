module Api
  module V1
    class CustomFieldsController < BaseController
      before_action :set_definition, only: %i[show update]
      before_action :ensure_resource_feature!

      def index
        resource_type = normalized_resource_type
        records = api_scope(CustomFieldDefinition, scope: "config:read")
                  .for_resource(resource_type).ordered
        render json: { data: records.map { |definition| Serialize.custom_field_definition(definition) } }
      end

      def show
        authorize_api!(@definition, :show?, scope: "config:read")
        render json: { data: Serialize.custom_field_definition(@definition) }
      end

      def create
        definition = CustomFieldDefinition.new(definition_params)
        authorize_api!(definition, :create?, scope: "config:write")
        if definition.save
          render json: { data: Serialize.custom_field_definition(definition) }, status: :created
        else
          render_validation_errors(definition)
        end
      end

      def update
        authorize_api!(@definition, :update?, scope: "config:write")
        if @definition.update(definition_params.except(:resource_type, :key))
          render json: { data: Serialize.custom_field_definition(@definition.reload) }
        else
          render_validation_errors(@definition)
        end
      end

      private

      def set_definition
        @definition = CustomFieldDefinition.find(params[:id])
      end

      def normalized_resource_type
        value = @definition&.resource_type || params[:resource_type] ||
                params.dig(:custom_field, :resource_type) || "cases"
        return value if CustomFieldDefinition::RESOURCE_TYPES.include?(value)

        raise ActionController::BadRequest, "unsupported custom-field resource"
      end

      def ensure_resource_feature!
        resource_type = normalized_resource_type
        ensure_feature!(CustomFieldDefinition.feature_for(resource_type))
      end

      def definition_params
        params.require(:custom_field).permit(
          :resource_type, :key, :label, :field_type, :required, :active, :reportable, :position,
          options: []
        )
      end
    end
  end
end
