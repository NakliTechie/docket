module Connectors
  # CRM/work-management effector for monday.com's API v2, which is a single
  # GraphQL endpoint (POST {base}/v2). Auth is a personal/API token sent RAW
  # in the Authorization header — NO "Bearer " prefix — alongside a pinned
  # API-Version header. The token is a secret kept in the credential vault;
  # the target board id and (optional) base override are non-secret config.
  #
  # Effector-only (syncs: false): the agent can create a board item. It is a
  # :confirm write — the AI prepares the item and a human signs off before it
  # lands on the board. The item name is passed as a GraphQL variable (not
  # interpolated into the query string) so there is no query-injection surface.
  class MondayProvider < HttpProvider
    DEFAULT_BASE = "https://api.monday.com".freeze
    API_VERSION = "2023-10".freeze

    def self.descriptor
      Descriptor.new(
        key: "monday", name: "monday.com", category: "CRM & Sales",
        auth: :none, config_fields: %w[board_id base_url],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_item", name: "Create item",
          summary: "Create a monday.com board item.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "Name of the item to create on the board" }
            },
            "required" => %w[name]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_item" then create_item(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    # POST {base}/v2 — GraphQL mutation. The board id is read from required
    # config; the item name flows in as a GraphQL variable so it cannot break
    # out of the query string.
    def create_item(args)
      name = blank_to_nil(args["name"] || args[:name])
      raise Connectors::Error, "name is required" if name.nil?

      board_id = require_config("board_id")
      query = "mutation ($boardId: ID!, $itemName: String!) { " \
              "create_item (board_id: $boardId, item_name: $itemName) { id } }"
      body = { "query" => query, "variables" => { "boardId" => board_id, "itemName" => name } }

      uri = build_uri(base, "/v2")
      response = ensure_ok!(post_json(uri, body, headers: auth_headers), "monday.com")
      { "ok" => true, "result" => parse_json(response.body) }
    end

    def auth_headers
      { "Authorization" => require_secret("api_token"), "API-Version" => API_VERSION }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
