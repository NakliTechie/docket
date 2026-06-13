module Connectors
  # Productivity effector for Airtable's REST API. Auth is a Personal Access
  # Token (PAT) sent as a Bearer header. The base defaults to
  # https://api.airtable.com (self-hosted/proxy tenants override it via the
  # base_url config). The target base_id and table_name are non-secret config.
  #
  # Effector-only (syncs: false): the agent can create a record in the
  # configured table. It is a :confirm write — the AI prepares the record's
  # fields and a human signs off before it lands in Airtable.
  class AirtableProvider < HttpProvider
    DEFAULT_BASE = "https://api.airtable.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "airtable", name: "Airtable", category: "Productivity",
        auth: :none, config_fields: %w[base_id table_name base_url],
        credential_fields: %w[access_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_record", name: "Create record",
          summary: "Create an Airtable record.",
          params: {
            "type" => "object",
            "properties" => {
              "fields" => {
                "type" => "object",
                "description" => "Field name → value map for the new record"
              }
            },
            "required" => %w[fields]
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

    # POST {base}/v0/{base_id}/{table_name} — JSON { fields: <fields object> }.
    # The table_name may contain spaces, so it is CGI-escaped into the path.
    def create_record(args)
      fields = args["fields"] || args[:fields]
      raise Connectors::Error, "fields is required" unless fields.is_a?(Hash) && fields.present?

      path = "/v0/#{require_config('base_id')}/#{CGI.escape(require_config('table_name'))}"
      uri = build_uri(base, path)
      response = ensure_ok!(post_json(uri, { "fields" => fields }, headers: auth_headers), "Airtable")
      { "ok" => true, "result" => parse_json(response.body) }
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
