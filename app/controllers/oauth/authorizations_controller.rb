module Oauth
  class AuthorizationsController < ApplicationController
    require_feature "mcp"

    def new
      @authorization_request = AuthorizationRequest.from_params(params)
      @request_token = @authorization_request.signed_token
    rescue Error => e
      render_error(e)
    end

    def create
      authorization_request = AuthorizationRequest.from_token(params[:request_token])
      if params[:decision] == "deny"
        return redirect_to authorization_request.redirect_with(
          error: "access_denied", state: authorization_request.state
        ), allow_other_host: true
      end

      selected_scopes = Array(params[:scopes]).map(&:to_s).uniq
      unless selected_scopes.any? && (selected_scopes - authorization_request.scopes).empty?
        raise Error.new("invalid_scope", "select at least one requested scope")
      end

      code = OauthAuthorizationCode.issue!(
        oauth_client: authorization_request.client, user: Current.user,
        redirect_uri: authorization_request.redirect_uri,
        code_challenge: authorization_request.code_challenge,
        scopes: selected_scopes, resource: authorization_request.resource
      )
      AuditEntry.append!(action: "oauth.authorization_granted", auditable: code.oauth_client,
                         actor: Current.user, metadata: { scopes: selected_scopes, resource: code.resource })
      redirect_to authorization_request.redirect_with(code: code.raw_code, state: authorization_request.state),
                  allow_other_host: true
    rescue Error => e
      render_error(e)
    end

    private

    def render_error(error)
      render plain: [ error.code, error.description ].compact.join(": "), status: error.status
    end
  end
end
