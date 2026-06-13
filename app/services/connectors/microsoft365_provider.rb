module Connectors
  # OAuth2 provider: Outlook mail + calendar via Microsoft Graph. The operator
  # registers an Entra ID (Azure AD) app (client_id config + client_secret
  # credential) on the multi-tenant `common` endpoint, connects once through the
  # browser, then the agent can send mail or place a calendar event. Both are
  # :confirm — the AI prepares and a human confirms before it takes effect.
  # offline_access in the scope is what yields a refresh token. Effector-only.
  class Microsoft365Provider < OauthProvider
    API_BASE = "https://graph.microsoft.com".freeze

    def self.authorize_endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    def self.token_endpoint     = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    def self.oauth_scope        = "offline_access Mail.Send Calendars.ReadWrite"

    def self.descriptor
      Descriptor.new(
        key: "microsoft365", name: "Microsoft 365 (Outlook)", category: "Productivity",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_mail", name: "Send email",
          summary: "Send an email from the connected Outlook account.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient address(es), comma-separated" },
              "subject" => { "type" => "string", "description" => "Subject line" },
              "body" => { "type" => "string", "description" => "Plain-text body" }
            },
            "required" => %w[to subject body]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "create_event", name: "Create calendar event",
          summary: "Create an event on the connected Outlook calendar.",
          params: {
            "type" => "object",
            "properties" => {
              "subject" => { "type" => "string", "description" => "Event title" },
              "start_time" => { "type" => "string", "description" => "Start, ISO 8601 (e.g. 2026-07-01T10:00:00)" },
              "end_time" => { "type" => "string", "description" => "End, ISO 8601" },
              "time_zone" => { "type" => "string", "description" => "IANA/Windows time zone (default UTC)" },
              "body" => { "type" => "string", "description" => "Event body/notes (optional)" }
            },
            "required" => %w[subject start_time end_time]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_mail"    then send_mail(args)
      when "create_event" then create_event(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_mail(args)
      recipients = require_arg(args, "to").split(",").map(&:strip).reject(&:empty?)
        .map { |addr| { "emailAddress" => { "address" => addr } } }
      message = {
        "subject" => require_arg(args, "subject"),
        "body" => { "contentType" => "Text", "content" => require_arg(args, "body") },
        "toRecipients" => recipients
      }
      uri = build_uri(API_BASE, "/v1.0/me/sendMail")
      ensure_ok!(post_json(uri, { "message" => message, "saveToSentItems" => true }, headers: auth_headers), "Microsoft Graph")
      { "ok" => true } # Graph sendMail returns 202 Accepted with no body
    end

    def create_event(args)
      tz = (args["time_zone"] || args[:time_zone]).to_s.strip.presence || "UTC"
      body = {
        "subject" => require_arg(args, "subject"),
        "start" => { "dateTime" => require_arg(args, "start_time"), "timeZone" => tz },
        "end" => { "dateTime" => require_arg(args, "end_time"), "timeZone" => tz }
      }
      notes = (args["body"] || args[:body]).to_s
      body["body"] = { "contentType" => "Text", "content" => notes } if notes.present?

      uri = build_uri(API_BASE, "/v1.0/me/events")
      resp = ensure_ok!(post_json(uri, body, headers: auth_headers), "Microsoft Graph")
      { "ok" => true, "event" => parse_json(resp.body) }
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
