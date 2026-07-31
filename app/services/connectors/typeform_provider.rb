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
      records = []
      before = nil
      seen = Set.new

      loop do
        query = { page_size: 1_000 }
        query[:since] = (connector.last_synced_at - 5.minutes).to_i if connector.last_synced_at
        query[:before] = before if before.present?
        uri = build_uri(base, "/forms/#{require_config('form_id')}/responses?#{URI.encode_www_form(query)}")
        response = ensure_ok!(get(uri, headers: auth_headers), "Typeform")
        body = parse_json(response.body)
        raise Connectors::Error, "Typeform returned an invalid responses page" unless body.is_a?(Hash)

        items = body["items"]
        items = [] if items.nil? && body["total_items"].to_i.zero?
        raise Connectors::Error, "Typeform responses page is missing items" unless items.is_a?(Array)
        records.concat(items.select { |record| record.is_a?(Hash) })
        break if items.length < 1_000

        before = items.last.is_a?(Hash) ? items.last["token"].to_s.presence : nil
        raise Connectors::Error, "Typeform did not provide a pagination token" unless before
        raise Connectors::Error, "Typeform repeated its pagination token" unless seen.add?(before)
      end

      records
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
