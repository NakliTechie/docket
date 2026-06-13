module Connectors
  # Effector-only Asana productivity provider. Auth is a Personal Access
  # Token (PAT) carried as a static Bearer header on every request; the token
  # is a secret kept in the credential vault. An optional `project_id`
  # (non-secret config) scopes created tasks to a project, and an optional
  # `base_url` overrides the default API host (handy for region/proxy setups).
  #
  # Asana wraps both request and response payloads in a top-level `data`
  # envelope, so create_task POSTs { "data" => { ... } } and reads back the
  # created task from the response's "data" key. The single action creates a
  # task; it writes a record into the workspace, so it defaults to :confirm —
  # the AI drafts, a human confirms before it lands in Asana.
  class AsanaProvider < HttpProvider
    DEFAULT_BASE = "https://app.asana.com/api/1.0".freeze

    def self.descriptor
      Descriptor.new(
        key: "asana", name: "Asana", category: "Productivity",
        auth: :none, config_fields: %w[project_id base_url],
        credential_fields: %w[access_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_task", name: "Create task",
          summary: "Create an Asana task.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "Name (title) of the task" },
              "notes" => { "type" => "string", "description" => "Free-form notes / description for the task" }
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

    # POST /tasks — Asana wraps the payload in a top-level "data" object and
    # takes the owning project as a "projects" array of gids.
    def create_task(args)
      name = blank_to_nil(args["name"] || args[:name])
      raise Connectors::Error, "name is required" if name.nil?

      data = { "name" => name }
      notes = blank_to_nil(args["notes"] || args[:notes])
      data["notes"] = notes unless notes.nil?
      project_id = blank_to_nil(connector.config_value("project_id"))
      data["projects"] = [ project_id ] unless project_id.nil?

      uri = build_uri(base, "/tasks")
      response = ensure_ok!(post_json(uri, { "data" => data }, headers: auth_headers), "Asana")
      { "ok" => true, "result" => parse_json(response.body) }
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
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
