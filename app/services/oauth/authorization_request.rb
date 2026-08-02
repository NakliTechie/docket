module Oauth
  class AuthorizationRequest
    TOKEN_PURPOSE = "mcp_oauth_authorization_request".freeze
    TOKEN_TTL = 10.minutes
    CHALLENGE_PATTERN = /\A[A-Za-z0-9_-]{43}\z/

    attr_reader :client, :redirect_uri, :code_challenge, :scopes, :state, :resource

    def self.from_params(params)
      new(
        client_id: params[:client_id], response_type: params[:response_type],
        redirect_uri: params[:redirect_uri], code_challenge: params[:code_challenge],
        code_challenge_method: params[:code_challenge_method], scope: params[:scope],
        state: params[:state], resource: params[:resource]
      )
    end

    def self.from_token(token)
      payload = Rails.application.message_verifier(TOKEN_PURPOSE).verify(token)
      new(**payload.symbolize_keys)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise Error.new("invalid_request", "authorization request expired or was altered")
    end

    def initialize(client_id:, response_type:, redirect_uri:, code_challenge:, code_challenge_method:,
                   scope: nil, state: nil, resource: nil)
      @client = OauthClient.active.find_by(client_id: client_id.to_s)
      @redirect_uri = redirect_uri.to_s
      @code_challenge = code_challenge.to_s
      @scopes = normalize_scopes(scope)
      @state = state.to_s.presence
      @resource = resource.to_s.presence || Metadata.resource
      validate!(response_type.to_s, code_challenge_method.to_s)
    end

    def signed_token
      Rails.application.message_verifier(TOKEN_PURPOSE).generate(
        {
          client_id: client.client_id, response_type: "code", redirect_uri: redirect_uri,
          code_challenge: code_challenge, code_challenge_method: "S256",
          scope: scopes.join(" "), state: state, resource: resource
        },
        expires_in: TOKEN_TTL
      )
    end

    def redirect_with(params)
      uri = URI.parse(redirect_uri)
      existing = Rack::Utils.parse_nested_query(uri.query)
      uri.query = existing.merge(params.compact.stringify_keys).to_query
      uri.to_s
    end

    private

    def normalize_scopes(value)
      values = value.to_s.split.uniq
      values = Metadata.authorization_scopes if values.empty?
      values
    end

    def validate!(response_type, code_challenge_method)
      raise Error.new("invalid_request", "unknown OAuth client") unless client
      raise Error.new("unsupported_response_type") unless response_type == "code"
      raise Error.new("invalid_request", "redirect_uri is not registered") unless client.redirect_uri_allowed?(redirect_uri)
      raise Error.new("invalid_request", "PKCE S256 is required") unless code_challenge_method == "S256"
      raise Error.new("invalid_request", "invalid PKCE challenge") unless code_challenge.match?(CHALLENGE_PATTERN)
      raise Error.new("invalid_scope") if (scopes - Metadata.authorization_scopes).any?
      raise Error.new("invalid_target", "resource does not identify this MCP server") unless resource == Metadata.resource
    end
  end
end
