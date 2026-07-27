module Api
  module V1
    class OpenapiController < ActionController::API
      include TenantResolution

      # The spec describes only what this tenant has. Documenting endpoints
      # that answer 403 feature_disabled sends integrators to build against a
      # surface they don't own.
      def show
        doc = Docket::Openapi.document.deep_dup
        paths = doc[:paths] || doc["paths"]
        paths&.select! { |path, _| Features.api_path_enabled?(path) }
        render json: doc
      end
    end
  end
end
