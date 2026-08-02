module Api
  module V1
    class CustomFieldReportsController < BaseController
      def index
        resource_type = normalized_resource_type
        ensure_feature!(CustomFieldDefinition.feature_for(resource_type))
        scope_name = CustomFieldDefinition.api_read_scope_for(resource_type)
        model = CustomFieldDefinition.model_for(resource_type)
        definition = CustomFieldDefinition.for_resource(resource_type).reportable.find_by!(key: params.require(:field))
        scope = api_scope(model, scope: scope_name)
        render json: { data: CustomFieldReport.new(definition: definition, scope: scope).as_json }
      end

      private

      def normalized_resource_type
        value = params[:resource_type].presence || "cases"
        return value if CustomFieldDefinition::RESOURCE_TYPES.include?(value)

        raise ActionController::BadRequest, "unsupported custom-field resource"
      end
    end
  end
end
