module Connectors
  # Effector-only Notion provider. Auth is a static integration token (an
  # "internal integration secret") carried as a Bearer credential, paired with
  # the required "Notion-Version" header pinned to the stable "2022-06-28" API
  # so the response envelope stays predictable. The single action creates a
  # page (a row) inside a configured Notion database; the target database is a
  # non-secret config value (`database_id`). Creating a page is a discretionary
  # write into a record store, so it defaults to :confirm — the AI drafts the
  # row, a human confirms before it lands in Notion.
  class NotionProvider < HttpProvider
    DEFAULT_BASE = "https://api.notion.com".freeze
    NOTION_VERSION = "2022-06-28".freeze

    def self.descriptor
      Descriptor.new(
        key: "notion", name: "Notion", category: "Productivity",
        auth: :none, config_fields: %w[database_id base_url],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_page", name: "Create page",
          summary: "Create a Notion database page (row).",
          params: {
            "type" => "object",
            "properties" => {
              "title" => { "type" => "string", "description" => "Title of the page (the 'Name' property)" }
            },
            "required" => %w[title]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_page" then create_page(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_page(args)
      title = blank_to_nil(args["title"] || args[:title])
      raise Connectors::Error, "title is required" if title.nil?

      body = {
        "parent" => { "database_id" => require_config("database_id") },
        "properties" => {
          "Name" => { "title" => [ { "text" => { "content" => title } } ] }
        }
      }

      uri = build_uri(base, "/v1/pages")
      response = ensure_ok!(post_json(uri, body, headers: auth_headers), "Notion")
      { "ok" => true, "result" => parse_json(response.body) }
    end

    def auth_headers
      {
        "Authorization" => bearer(require_secret("api_token")),
        "Notion-Version" => NOTION_VERSION
      }
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
