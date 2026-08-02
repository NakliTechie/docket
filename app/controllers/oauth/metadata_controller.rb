module Oauth
  class MetadataController < ActionController::API
    include TenantResolution
    include FeatureGating

    require_feature "mcp"

    def protected_resource
      render json: Metadata.protected_resource
    end

    def authorization_server
      render json: Metadata.authorization_server
    end
  end
end
