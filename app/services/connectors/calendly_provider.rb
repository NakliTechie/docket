module Connectors
  # Calendly (v2 API). Static Personal-Access-Token credential (Bearer). The
  # agent can read scheduled events (autonomous) and mint a single-use
  # scheduling link to send a contact (:confirm). Effector-only. The owner's
  # Calendly `user_uri` (https://api.calendly.com/users/...) is configured once;
  # event-type URIs are passed per call.
  class CalendlyProvider < HttpProvider
    DEFAULT_BASE = "https://api.calendly.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "calendly", name: "Calendly", category: "Productivity",
        auth: :none, config_fields: %w[user_uri base_url],
        credential_fields: %w[access_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_events", name: "List scheduled events",
          summary: "List the owner's scheduled Calendly events.",
          params: {
            "type" => "object",
            "properties" => {
              "count" => { "type" => "integer", "description" => "Max events to return (default 20, max 100)" },
              "status" => { "type" => "string", "description" => "Filter by status: active or canceled (optional)" }
            }
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "create_scheduling_link", name: "Create scheduling link",
          summary: "Create a single-use Calendly scheduling link for an event type.",
          params: {
            "type" => "object",
            "properties" => {
              "event_type_uri" => { "type" => "string", "description" => "Calendly event-type URI to book against" }
            },
            "required" => %w[event_type_uri]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "list_events" then list_events(args)
      when "create_scheduling_link" then create_scheduling_link(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def list_events(args)
      params = { "user" => require_config("user_uri"), "count" => count(args) }
      status = (args["status"] || args[:status]).to_s.strip
      params["status"] = status if status.present?
      uri = build_uri(base, "/scheduled_events?#{URI.encode_www_form(params)}")
      resp = ensure_ok!(get(uri, headers: auth_headers), "Calendly")
      body = parse_json(resp.body)
      { "ok" => true, "events" => (body.is_a?(Hash) ? Array(body["collection"]) : []) }
    end

    def create_scheduling_link(args)
      event_type = require_arg(args, "event_type_uri")
      body = { "max_event_count" => 1, "owner" => event_type, "owner_type" => "EventType" }
      uri = build_uri(base, "/scheduling_links")
      resp = ensure_ok!(post_json(uri, body, headers: auth_headers), "Calendly")
      { "ok" => true, "link" => parse_json(resp.body) }
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def count(args)
      n = (args["count"] || args[:count]).to_i
      return 20 if n <= 0
      [ n, 100 ].min
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
