module Connectors
  # OAuth2 provider: create records in Microsoft Dynamics 365 (Dataverse) via
  # the Web API. Auth is Entra ID (Azure AD) on the multi-tenant `common`
  # endpoint, but Dataverse needs a *resource-scoped* grant — the scope is the
  # org's environment URL + "/.default", which is per-connector — so we override
  # the authorize URL to build it from the configured `resource_url`. API calls
  # target that same host. Writes are :confirm. Effector-only.
  class Dynamics365Provider < OauthProvider
    DEFAULT_API_VERSION = "v9.2".freeze

    def self.authorize_endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    def self.token_endpoint     = "https://login.microsoftonline.com/common/oauth2/v2.0/token"

    def self.descriptor
      Descriptor.new(
        key: "dynamics365", name: "Microsoft Dynamics 365", category: "CRM & Sales",
        auth: :none, config_fields: %w[client_id resource_url api_version],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    # The Dataverse scope is environment-specific, so build it from the
    # connector's resource_url rather than a fixed class-level scope.
    def self.authorize_url(connector, redirect_uri:, state:)
      resource = connector.config_value("resource_url").to_s.chomp("/")
      scope = [ ("#{resource}/.default" if resource.present?), "offline_access" ].compact.join(" ")
      params = {
        "client_id" => connector.config_value("client_id"),
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => scope,
        "state" => state
      }.reject { |_, v| v.to_s.empty? }
      "#{authorize_endpoint}?#{URI.encode_www_form(params)}"
    end

    def self.actions
      [
        Action.new(
          key: "create_record", name: "Create record",
          summary: "Create a Dynamics 365 record in an entity set (leads, contacts, accounts, …).",
          params: {
            "type" => "object",
            "properties" => {
              "entity_set" => { "type" => "string", "description" => "Entity set name (plural), e.g. leads, contacts, accounts" },
              "fields" => { "type" => "object", "description" => "Attribute → value map for the new record" }
            },
            "required" => %w[entity_set fields]
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

    private

    def create_record(args)
      entity_set = require_arg(args, "entity_set")
      fields = args["fields"] || args[:fields]
      raise Connectors::Error, "fields must be a non-empty object" unless fields.is_a?(Hash) && fields.any?

      headers = auth_headers.merge("Prefer" => "return=representation")
      uri = build_uri(resource_url, "/api/data/#{api_version}/#{CGI.escape(entity_set)}")
      resp = ensure_ok!(post_json(uri, fields, headers: headers), "Dynamics 365")
      { "ok" => true, "record" => parse_json(resp.body) }
    end

    def resource_url
      require_config("resource_url").chomp("/")
    end

    def api_version
      connector.config_value("api_version").to_s.strip.presence || DEFAULT_API_VERSION
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
