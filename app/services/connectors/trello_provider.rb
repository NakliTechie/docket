module Connectors
  # Effector-only provider: create a card on a configured Trello list.
  # Auth is unusual — there is NO Authorization header. Trello takes the API
  # key + token AND every action param in the QUERY STRING, so the request
  # body is empty and the path assertion is the auth assertion. Creating a card
  # is a discretionary write a human should confirm → :confirm. No inbound
  # sync (syncs: false).
  class TrelloProvider < HttpProvider
    DEFAULT_BASE = "https://api.trello.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "trello", name: "Trello", category: "Productivity",
        auth: :none, config_fields: %w[id_list base_url], credential_fields: %w[key token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_card", name: "Create card",
          summary: "Create a Trello card on the configured list.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "Card title" },
              "desc" => { "type" => "string", "description" => "Card description (optional)" }
            },
            "required" => %w[name]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_card" then create_card(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_card(args)
      name = (args["name"] || args[:name]).to_s.strip
      raise Connectors::Error, "name is required" if name.blank?

      desc = (args["desc"] || args[:desc]).to_s
      query = URI.encode_www_form(
        key: require_secret("key"), token: require_secret("token"),
        idList: require_config("id_list"), name: name, desc: desc
      )
      uri = build_uri(base, "/1/cards?#{query}")
      resp = post_json(uri, {})
      ensure_ok!(resp, "Trello")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
