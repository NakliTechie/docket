module Oauth
  class TokensController < ActionController::API
    include TenantResolution

    def create
      payload = grant_payload
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: payload
    rescue Error => e
      response.set_header("WWW-Authenticate", Metadata.challenge(error: e.code)) if e.status == :unauthorized
      render json: { error: e.code, error_description: e.description }.compact, status: e.status
    end

    private

    def grant_payload
      case params[:grant_type]
      when "client_credentials" then client_credentials_grant
      when "authorization_code" then authorization_code_grant
      when "refresh_token" then refresh_token_grant
      else raise Error.new("unsupported_grant_type")
      end
    end

    def client_credentials_grant
      client_id, client_secret = service_account_credentials
      account = ServiceAccount.authenticate(client_id.to_s, client_secret.to_s)
      raise Error.new("invalid_client", nil, status: :unauthorized) unless account

      token = account.issue_access_token!
      AuditEntry.append!(action: "service_account.token_issued", auditable: account, actor: account,
                         metadata: { ip: request.remote_ip })
      access_token_response(token)
    end

    def authorization_code_grant
      client = ClientAuthentication.call(params: params, authorization: request.authorization)
      code = OauthAuthorizationCode.find_by(code_digest: OauthAuthorizationCode.digest(params[:code]))
      raise Error.new("invalid_grant") unless code && code.oauth_client == client

      token = nil
      refresh = nil
      code.with_lock do
        validate_code!(code)
        code.update!(consumed_at: Time.current)
        token = OauthAccessToken.issue!(user: code.user, oauth_client: client,
                                        scopes: code.scopes, resource: code.resource)
        if client.grant_types.include?("refresh_token")
          refresh = OauthRefreshToken.issue!(oauth_client: client, user: code.user,
                                              scopes: code.scopes, resource: code.resource)
        end
      end
      access_token_response(token, refresh_token: refresh&.raw_token)
    end

    def refresh_token_grant
      client = ClientAuthentication.call(params: params, authorization: request.authorization)
      current = OauthRefreshToken.find_by(token_digest: OauthRefreshToken.digest(params[:refresh_token]))
      raise Error.new("invalid_grant") unless current && current.oauth_client == client

      token = nil
      replacement = nil
      current.with_lock do
        raise Error.new("invalid_grant") unless current.usable?
        raise Error.new("invalid_target") unless requested_resource == current.resource

        current.update!(revoked_at: Time.current)
        token = OauthAccessToken.issue!(user: current.user, oauth_client: client,
                                        scopes: current.scopes, resource: current.resource)
        replacement = OauthRefreshToken.issue!(oauth_client: client, user: current.user,
                                                scopes: current.scopes, resource: current.resource)
      end
      access_token_response(token, refresh_token: replacement.raw_token)
    end

    def validate_code!(code)
      raise Error.new("invalid_grant") unless code.usable?
      raise Error.new("invalid_grant") unless code.redirect_uri == params[:redirect_uri].to_s
      raise Error.new("invalid_grant") unless code.pkce_matches?(params[:code_verifier])
      raise Error.new("invalid_target") unless requested_resource == code.resource
    end

    def requested_resource
      params[:resource].to_s.presence || Metadata.resource
    end

    def access_token_response(token, refresh_token: nil)
      {
        access_token: token.raw_token,
        token_type: "Bearer",
        expires_in: (token.expires_at - Time.current).to_i,
        scope: token.scopes.join(" "),
        refresh_token: refresh_token
      }.compact
    end

    def service_account_credentials
      if request.authorization.to_s.start_with?("Basic ")
        decoded = Base64.strict_decode64(request.authorization.split(" ", 2).last)
        decoded.split(":", 2)
      else
        [ params[:client_id], params[:client_secret] ]
      end
    rescue ArgumentError
      [ nil, nil ]
    end
  end
end
