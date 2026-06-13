module Connectors
  # OAuth2 provider: create/update Salesforce sObjects via the REST API. The
  # operator registers a Connected App (client_id config + client_secret
  # credential) and connects once through the browser. Salesforce returns an
  # `instance_url` alongside the token — every API call targets THAT host, so we
  # persist it with the token bundle. Writes are :confirm. Effector-only for now
  # (inbound SOQL sync is a later Connectors::Sync target).
  class SalesforceProvider < OauthProvider
    DEFAULT_API_VERSION = "v59.0".freeze

    def self.authorize_endpoint = "https://login.salesforce.com/services/oauth2/authorize"
    def self.token_endpoint     = "https://login.salesforce.com/services/oauth2/token"
    def self.oauth_scope        = "api refresh_token"

    def self.descriptor
      Descriptor.new(
        key: "salesforce", name: "Salesforce", category: "CRM & Sales",
        auth: :none, config_fields: %w[client_id api_version],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_record", name: "Create record",
          summary: "Create a Salesforce record (Lead, Contact, Account, …).",
          params: {
            "type" => "object",
            "properties" => {
              "sobject" => { "type" => "string", "description" => "sObject type, e.g. Lead, Contact, Account" },
              "fields" => { "type" => "object", "description" => "Field name → value map for the new record" }
            },
            "required" => %w[sobject fields]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "update_record", name: "Update record",
          summary: "Update fields on an existing Salesforce record by id.",
          params: {
            "type" => "object",
            "properties" => {
              "sobject" => { "type" => "string", "description" => "sObject type" },
              "id" => { "type" => "string", "description" => "Record id" },
              "fields" => { "type" => "object", "description" => "Field name → value map to update" }
            },
            "required" => %w[sobject id fields]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_record" then create_record(args)
      when "update_record" then update_record(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_record(args)
      sobject = require_arg(args, "sobject")
      fields = require_fields(args)
      uri = build_uri(instance_url, "/services/data/#{api_version}/sobjects/#{CGI.escape(sobject)}/")
      resp = ensure_ok!(post_json(uri, fields, headers: auth_headers), "Salesforce")
      { "ok" => true, "record" => parse_json(resp.body) }
    end

    def update_record(args)
      sobject = require_arg(args, "sobject")
      id = require_arg(args, "id")
      fields = require_fields(args)
      uri = build_uri(instance_url, "/services/data/#{api_version}/sobjects/#{CGI.escape(sobject)}/#{CGI.escape(id)}")
      ensure_ok!(patch_json(uri, fields, headers: auth_headers), "Salesforce") # 204 No Content on success
      { "ok" => true, "id" => id }
    end

    # Salesforce hands back the per-org instance_url with the token; persist it
    # so subsequent calls (and refreshes) target the right host.
    def store_tokens!(tokens)
      result = super
      if tokens["instance_url"].present?
        connector.oauth_tokens = connector.oauth_tokens.merge("instance_url" => tokens["instance_url"])
        connector.save!
      end
      result
    end

    def instance_url
      url = connector.oauth_tokens["instance_url"].to_s
      raise Connectors::Error, "connector is not connected (no instance_url)" if url.blank?
      url
    end

    def api_version
      connector.config_value("api_version").to_s.strip.presence || DEFAULT_API_VERSION
    end

    def require_fields(args)
      fields = args["fields"] || args[:fields]
      raise Connectors::Error, "fields must be a non-empty object" unless fields.is_a?(Hash) && fields.any?
      fields
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
