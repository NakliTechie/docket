module Connectors
  # Base for OAuth2 (authorization-code) providers. The operator registers an
  # OAuth app with the vendor, supplies client_id (config) + client_secret
  # (credential), then completes a browser connect (Admin::ConnectorOauthController)
  # that exchanges the returned code for an access+refresh token bundle stored
  # on the connector (Connector#oauth_credentials, encrypted). This base owns the
  # token-endpoint dance and transparent refresh-on-expiry; a subclass declares
  # the endpoints + scope and implements its actions using #auth_headers, which
  # always yields a currently-valid Bearer token.
  #
  #   class FooProvider < OauthProvider
  #     def self.authorize_endpoint = "https://foo.com/oauth/authorize"
  #     def self.token_endpoint     = "https://foo.com/oauth/token"
  #     def self.oauth_scope        = "read write"
  #     # descriptor: config_fields must include "client_id"; credential_fields "client_secret"
  #     def invoke(key, args, _ctx = {})
  #       ... post_json(build_uri(api_base, path), body, headers: auth_headers) ...
  #     end
  #   end
  class OauthProvider < HttpProvider
    EXPIRY_SKEW = 60 # refresh slightly before the recorded expiry

    class << self
      def authorize_endpoint = raise(NotImplementedError, "#{name} must define .authorize_endpoint")
      def token_endpoint     = raise(NotImplementedError, "#{name} must define .token_endpoint")
      def oauth_scope        = ""
      # Vendor-specific extras on the authorize URL (e.g. Google's
      # access_type=offline + prompt=consent to mint a refresh token).
      def extra_authorize_params = {}

      # The vendor authorization URL to redirect the operator's browser to.
      def authorize_url(connector, redirect_uri:, state:)
        params = {
          "client_id" => connector.config_value("client_id"),
          "redirect_uri" => redirect_uri,
          "response_type" => "code",
          "scope" => oauth_scope,
          "state" => state
        }.merge(extra_authorize_params).reject { |_, v| v.to_s.empty? }
        "#{authorize_endpoint}?#{URI.encode_www_form(params)}"
      end
    end

    # Exchange an authorization code for tokens and persist them — called by the
    # OAuth callback controller once the operator has authorized.
    def exchange_code!(code, redirect_uri:)
      store_tokens!(token_request(
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri
      ))
    end

    # Bearer header with a currently-valid access token (refreshing first if it
    # has expired and we hold a refresh token). Subclass actions call this.
    def auth_headers
      { "Authorization" => bearer(access_token) }
    end

    def access_token
      refresh! if token_expired? && refresh_token.present?
      token = connector.oauth_tokens["access_token"].to_s
      raise Connectors::Error, "connector is not connected (no access token)" if token.blank?
      token
    end

    private

    def refresh!
      tokens = token_request("grant_type" => "refresh_token", "refresh_token" => refresh_token)
      tokens["refresh_token"] ||= refresh_token # a refresh response may omit it — keep ours
      store_tokens!(tokens)
    end

    def token_request(params)
      uri = build_uri(self.class.token_endpoint)
      form = params.merge("client_id" => require_config("client_id"), "client_secret" => require_secret("client_secret"))
      resp = ensure_ok!(post_form(uri, form), "#{self.class.name} token endpoint")
      body = parse_json(resp.body)
      raise Connectors::Error, "token endpoint returned no access_token" unless body.is_a?(Hash) && body["access_token"].present?
      body
    end

    def store_tokens!(tokens)
      current = connector.oauth_tokens
      expires_at = tokens["expires_in"] ? (Time.current + tokens["expires_in"].to_i.seconds).iso8601 : current["expires_at"]
      connector.oauth_tokens = current.merge(
        "access_token" => tokens["access_token"],
        "refresh_token" => tokens["refresh_token"] || current["refresh_token"],
        "token_type" => tokens["token_type"] || current["token_type"],
        "scope" => tokens["scope"] || current["scope"],
        "expires_at" => expires_at
      ).compact
      connector.save!
      tokens
    end

    def refresh_token
      connector.oauth_tokens["refresh_token"].to_s
    end

    def token_expired?
      exp = connector.oauth_tokens["expires_at"]
      return false if exp.blank? # no expiry recorded → assume valid; a 401 surfaces a stale token
      Time.parse(exp) <= Time.current + EXPIRY_SKEW
    rescue ArgumentError
      false
    end
  end
end
