module Connectors
  # OAuth2 reference provider: create events on a Google Calendar. The operator
  # registers a Google Cloud OAuth client (client_id config + client_secret
  # credential), connects once through the browser (the OauthProvider seam mints
  # + refreshes the token bundle), then the agent can place events. Creating an
  # event is :confirm — the AI prepares it and a human confirms before it lands.
  class GoogleCalendarProvider < OauthProvider
    API_BASE = "https://www.googleapis.com".freeze

    def self.authorize_endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    def self.token_endpoint     = "https://oauth2.googleapis.com/token"
    def self.oauth_scope        = "https://www.googleapis.com/auth/calendar.events"
    # offline + consent so Google returns a refresh token on first authorize.
    def self.extra_authorize_params = { "access_type" => "offline", "prompt" => "consent" }

    def self.descriptor
      Descriptor.new(
        key: "google_calendar", name: "Google Calendar", category: "Productivity",
        auth: :none, config_fields: %w[client_id calendar_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_event", name: "Create calendar event",
          summary: "Create an event on the connected Google Calendar.",
          params: {
            "type" => "object",
            "properties" => {
              "summary" => { "type" => "string", "description" => "Event title" },
              "start_time" => { "type" => "string", "description" => "Start, RFC3339 (e.g. 2026-07-01T10:00:00+05:30)" },
              "end_time" => { "type" => "string", "description" => "End, RFC3339" },
              "description" => { "type" => "string", "description" => "Event description" }
            },
            "required" => %w[summary start_time end_time]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_event" then create_event(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_event(args)
      body = {
        "summary" => require_arg(args, "summary"),
        "start" => { "dateTime" => require_arg(args, "start_time") },
        "end" => { "dateTime" => require_arg(args, "end_time") }
      }
      description = (args["description"] || args[:description]).to_s
      body["description"] = description if description.present?

      uri = build_uri(API_BASE, "/calendar/v3/calendars/#{CGI.escape(calendar_id)}/events")
      resp = ensure_ok!(post_json(uri, body, headers: auth_headers), "Google Calendar")
      { "ok" => true, "event" => parse_json(resp.body) }
    end

    def calendar_id
      connector.config_value("calendar_id").presence || "primary"
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
