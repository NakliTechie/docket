module Oauth
  module Metadata
    module_function

    def issuer
      Docket::TenantUrl.base_url
    end

    def resource
      "#{issuer}/api/v1/mcp"
    end

    def protected_resource_url
      "#{issuer}/.well-known/oauth-protected-resource/api/v1/mcp"
    end

    def protected_resource
      {
        resource: resource,
        authorization_servers: [ issuer ],
        scopes_supported: ServiceAccount::SCOPES,
        bearer_methods_supported: [ "header" ]
      }
    end

    def authorization_scopes
      ServiceAccount::SCOPES + [ "offline_access" ]
    end

    def authorization_server
      {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        registration_endpoint: "#{issuer}/oauth/register",
        response_types_supported: [ "code" ],
        grant_types_supported: [ "authorization_code", "refresh_token", "client_credentials" ],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: OauthClient::AUTH_METHODS,
        scopes_supported: authorization_scopes,
        protected_resources: [ resource ]
      }
    end

    def challenge(scope: nil, error: nil)
      values = [ %(Bearer realm="docket-mcp"), %(resource_metadata="#{protected_resource_url}") ]
      values << %(scope="#{scope}") if scope.present?
      values << %(error="#{error}") if error.present?
      values.join(", ")
    end
  end
end
