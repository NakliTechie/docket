module Api
  module V1
    class CustomFieldReportsController < BaseController
      def index
        resource_type = normalized_resource_type
        ensure_feature!(resource_type == "cases" ? "service_desk" : "work")
        scope_name = resource_type == "cases" ? "cases:read" : "work:read"
        model = resource_type == "cases" ? Case : WorkItem
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
