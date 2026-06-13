module Connectors
  # Effector-only productivity provider for ClickUp's v2 API. Auth is a
  # personal/API token sent as the RAW value of the `Authorization` header —
  # ClickUp does NOT use a `Bearer ` prefix — kept in the credential vault.
  # The target list is non-secret config (`list_id`); the API base defaults to
  # https://api.clickup.com/api/v2 but can be overridden via `base_url` config.
  #
  # Effector-only (syncs: false): the agent can create a task. It writes a
  # record a human works, so it defaults to :confirm — the AI drafts the task
  # and a human signs off before it lands in the workspace.
  class ClickupProvider < HttpProvider
    DEFAULT_BASE = "https://api.clickup.com/api/v2".freeze

    def self.descriptor
      Descriptor.new(
        key: "clickup", name: "ClickUp", category: "Productivity",
        auth: :none, config_fields: %w[list_id base_url],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_task", name: "Create task",
          summary: "Create a ClickUp task.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "Task name (title)" },
              "description" => { "type" => "string", "description" => "Task description / body text" }
            },
            "required" => %w[name]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_task" then create_task(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    # POST {base}/list/{list_id}/task — JSON { name, description }.
    def create_task(args)
      name = blank_to_nil(arg(args, "name"))
      raise Connectors::Error, "name is required" if name.nil?

      body = { "name" => name }
      description = blank_to_nil(arg(args, "description"))
      body["description"] = description unless description.nil?

      uri = build_uri(base, "/list/#{require_config('list_id')}/task")
      resp = post_json(uri, body, headers: auth_headers)
      ensure_ok!(resp, "ClickUp")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    # ClickUp's Authorization header is the RAW token — no `Bearer ` prefix.
    def auth_headers
      { "Authorization" => require_secret("api_token") }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
