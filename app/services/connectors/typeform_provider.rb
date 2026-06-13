module Connectors
  # Sync-only provider for Typeform's Responses API. Auth is a Typeform
  # personal access token — a static Bearer credential — kept in the
  # credential vault. There are NO agent actions: this provider only pulls
  # form responses inbound (it inherits the default empty .actions and does
  # not implement #invoke). Each response maps onto a Lead via the connector
  # field-mapping. The base defaults to https://api.typeform.com and can be
  # overridden per-tenant with the base_url config value.
  class TypeformProvider < HttpProvider
    DEFAULT_BASE = "https://api.typeform.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "typeform", name: "Typeform", category: "Forms & Surveys",
        auth: :none, config_fields: %w[form_id base_url],
        credential_fields: %w[access_token], syncs: true
      )
    end

    # Pull form responses inbound; each maps onto a Lead via the connector
    # field-mapping. GET /forms/{form_id}/responses → { "items" => [...] }.
    def fetch
      uri = build_uri(base, "/forms/#{require_config('form_id')}/responses")
      response = ensure_ok!(get(uri, headers: auth_headers), "Typeform")
      body = parse_json(response.body)
      items = body.is_a?(Hash) ? body["items"] : body
      items.is_a?(Array) ? items : []
    end

    private

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
