module Connectors
  # Sync-only provider for Jotform's API. The agent does not write to Jotform;
  # it pulls form submissions inbound so each maps onto a Lead record. Auth is a
  # Jotform API key sent as the custom `APIKEY` header — a static credential kept
  # in the vault. The base defaults to https://api.jotform.com (EU/HIPAA tenants
  # override it via the base_url config). The form to pull is non-secret config.
  class JotformProvider < HttpProvider
    DEFAULT_BASE = "https://api.jotform.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "jotform", name: "Jotform", category: "Forms & Surveys",
        auth: :none, config_fields: %w[form_id base_url],
        credential_fields: %w[api_key], syncs: true
      )
    end

    # Pull form submissions inbound so each maps onto a Lead. Jotform wraps the
    # collection as { responseCode:, content: [...] } — we return the content
    # array of submission Hashes.
    def fetch
      uri = build_uri(base, "/form/#{require_config('form_id')}/submissions")
      response = ensure_ok!(get(uri, headers: auth_headers), "Jotform")
      body = parse_json(response.body)
      content = body.is_a?(Hash) ? body["content"] : nil
      Array(content).select { |r| r.is_a?(Hash) }
    end

    private

    def auth_headers
      { "APIKEY" => require_secret("api_key") }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
