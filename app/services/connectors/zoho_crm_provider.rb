module Connectors
  # OAuth2 provider: create Zoho CRM records via the v5 REST API. The operator
  # registers a Zoho API client (client_id config + client_secret credential)
  # and connects once through the browser. Two Zoho-isms the base doesn't
  # assume: the access token is sent as `Zoho-oauthtoken <token>` (not Bearer),
  # and the token response carries the per-account `api_domain` host (which
  # varies by data centre — .com / .in / .eu) that we persist and call against.
  # access_type=offline + prompt=consent are what yield a refresh token.
  # Effector-only for now. Authorize/token default to the .com data centre;
  # operators in another DC register the connector against that DC's accounts host.
  class ZohoCrmProvider < OauthProvider
    DEFAULT_API_DOMAIN = "https://www.zohoapis.com".freeze

    def self.authorize_endpoint = "https://accounts.zoho.com/oauth/v2/auth"
    def self.token_endpoint     = "https://accounts.zoho.com/oauth/v2/token"
    def self.oauth_scope        = "ZohoCRM.modules.ALL"
    def self.extra_authorize_params = { "access_type" => "offline", "prompt" => "consent" }

    def self.descriptor
      Descriptor.new(
        key: "zoho_crm", name: "Zoho CRM", category: "CRM & Sales",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_record", name: "Create record",
          summary: "Create a Zoho CRM record in a module (Leads, Contacts, Deals, …).",
          params: {
            "type" => "object",
            "properties" => {
              "module" => { "type" => "string", "description" => "CRM module API name, e.g. Leads, Contacts, Deals" },
              "fields" => { "type" => "object", "description" => "Field API name → value map for the new record" }
            },
            "required" => %w[module fields]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_record" then create_record(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    # Zoho uses its own auth scheme, not Bearer.
    def auth_headers
      { "Authorization" => "Zoho-oauthtoken #{access_token}" }
    end

    private

    def create_record(args)
      mod = require_arg(args, "module")
      fields = args["fields"] || args[:fields]
      raise Connectors::Error, "fields must be a non-empty object" unless fields.is_a?(Hash) && fields.any?

      uri = build_uri(api_domain, "/crm/v5/#{CGI.escape(mod)}")
      resp = ensure_ok!(post_json(uri, { "data" => [ fields ] }, headers: auth_headers), "Zoho CRM")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    # Persist the api_domain Zoho returns with the token bundle.
    def store_tokens!(tokens)
      result = super
      if tokens["api_domain"].present?
        connector.oauth_tokens = connector.oauth_tokens.merge("api_domain" => tokens["api_domain"])
        connector.save!
      end
      result
    end

    def api_domain
      connector.oauth_tokens["api_domain"].to_s.strip.presence || DEFAULT_API_DOMAIN
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
