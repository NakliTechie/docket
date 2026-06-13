module Connectors
  # Metabase (self-hosted BI). Static API-key credential in the `x-api-key`
  # header (Metabase 0.49+). The base host is the operator's own Metabase, so
  # base_url is required config. Read-only effector: list saved questions
  # (cards) and run one to pull its rows — lets an agent read a curated metric
  # without raw DB access. Effector-only.
  class MetabaseProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "metabase", name: "Metabase", category: "Data & BI",
        auth: :none, config_fields: %w[base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_cards", name: "List questions",
          summary: "List saved Metabase questions (cards).",
          params: { "type" => "object", "properties" => {} },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "run_card", name: "Run question",
          summary: "Run a saved Metabase question and return its rows.",
          params: {
            "type" => "object",
            "properties" => {
              "card_id" => { "type" => "integer", "description" => "Saved question (card) id" }
            },
            "required" => %w[card_id]
          },
          effect: :read, decision_class: :autonomous
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "list_cards" then list_cards
      when "run_card" then run_card(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def list_cards
      uri = build_uri(base, "/api/card")
      resp = ensure_ok!(get(uri, headers: auth_headers), "Metabase")
      body = parse_json(resp.body)
      { "ok" => true, "cards" => (body.is_a?(Array) ? body : []) }
    end

    def run_card(args)
      card_id = (args["card_id"] || args[:card_id]).to_s.strip
      raise Connectors::Error, "card_id is required" if card_id.blank?
      uri = build_uri(base, "/api/card/#{CGI.escape(card_id)}/query/json")
      resp = ensure_ok!(post_json(uri, {}, headers: auth_headers), "Metabase")
      { "ok" => true, "rows" => parse_json(resp.body) }
    end

    def auth_headers
      { "x-api-key" => require_secret("api_key") }
    end

    def base
      require_config("base_url").chomp("/")
    end
  end
end
