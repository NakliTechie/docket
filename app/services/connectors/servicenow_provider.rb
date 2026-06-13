module Connectors
  # Effector-only provider: open a ServiceNow incident via the Table API.
  # Auth is Basic auth (username:password, both vaulted). The base is derived
  # per-tenant from the instance name: https://{instance}.service-now.com.
  # Opening an incident touches a citizen-facing ITSM record of work, so the
  # single write defaults to :confirm — the AI drafts, a human confirms before
  # it lands in the service desk.
  class ServicenowProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "servicenow", name: "ServiceNow (ITSM)", category: "Support & Ticketing",
        auth: :none, config_fields: %w[instance], credential_fields: %w[username password], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_incident", name: "Create incident",
          summary: "Open a ServiceNow incident.",
          params: {
            "type" => "object",
            "properties" => {
              "short_description" => { "type" => "string", "description" => "One-line summary of the incident" },
              "description" => { "type" => "string", "description" => "Optional: full incident detail" },
              "urgency" => { "type" => "string", "description" => "Optional: urgency code (1 high, 2 medium, 3 low)" }
            },
            "required" => %w[short_description]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_incident" then create_incident(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_incident(args)
      short_description = arg(args, "short_description")
      raise Connectors::Error, "short_description is required" if short_description.blank?

      body = { "short_description" => short_description }
      description = arg(args, "description")
      body["description"] = description if description.present?
      urgency = arg(args, "urgency")
      body["urgency"] = urgency if urgency.present?

      uri = build_uri(base, "/api/now/table/incident")
      resp = post_json(uri, body, headers: auth_headers)
      ensure_ok!(resp, "ServiceNow")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def base
      "https://#{require_config('instance')}.service-now.com"
    end

    def auth_headers
      { "Authorization" => basic_auth(require_secret("username"), require_secret("password")) }
    end
  end
end
