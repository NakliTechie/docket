module Oauth
  class RegistrationsController < ActionController::API
    include TenantResolution
    include FeatureGating

    require_feature "mcp"

    def create
      client = OauthClient.create!(registration_params)
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: registration_response(client), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: "invalid_client_metadata", error_description: e.record.errors.full_messages.join(", ") },
             status: :bad_request
    end

    private

    def registration_params
      permitted = params.permit(:client_name, :token_endpoint_auth_method,
                                redirect_uris: [], grant_types: [], response_types: [])
      {
        client_name: permitted[:client_name].presence || "MCP client",
        token_endpoint_auth_method: permitted[:token_endpoint_auth_method].presence || "none",
        redirect_uris: Array(permitted[:redirect_uris]),
        grant_types: Array(permitted[:grant_types]).presence || [ "authorization_code", "refresh_token" ],
        response_types: Array(permitted[:response_types]).presence || [ "code" ]
      }
    end

    def registration_response(client)
      {
        client_id: client.client_id,
        client_id_issued_at: client.created_at.to_i,
        client_name: client.client_name,
        redirect_uris: client.redirect_uris,
        grant_types: client.grant_types,
        response_types: client.response_types,
        token_endpoint_auth_method: client.token_endpoint_auth_method
      }.tap do |body|
        if client.confidential?
          body[:client_secret] = client.raw_client_secret
          body[:client_secret_expires_at] = 0
        end
      end
    end
  end
end
