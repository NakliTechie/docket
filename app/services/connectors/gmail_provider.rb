module Connectors
  # OAuth2 provider: send mail as the connected Google account via the Gmail
  # API. The operator registers a Google Cloud OAuth client (client_id config +
  # client_secret credential), connects once through the browser (the
  # OauthProvider seam mints + refreshes the token bundle), then the agent can
  # send email. Sending is :confirm — the AI drafts it and a human confirms
  # before it leaves the outbox. Effector-only (no inbound sync).
  class GmailProvider < OauthProvider
    API_BASE = "https://gmail.googleapis.com".freeze

    def self.authorize_endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    def self.token_endpoint     = "https://oauth2.googleapis.com/token"
    def self.oauth_scope        = "https://www.googleapis.com/auth/gmail.send"
    # offline + consent so Google returns a refresh token on first authorize.
    def self.extra_authorize_params = { "access_type" => "offline", "prompt" => "consent" }

    def self.descriptor
      Descriptor.new(
        key: "gmail", name: "Gmail (send)", category: "Productivity",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_email", name: "Send email",
          summary: "Send an email from the connected Gmail account.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient email address" },
              "subject" => { "type" => "string", "description" => "Subject line" },
              "body" => { "type" => "string", "description" => "Plain-text body" },
              "cc" => { "type" => "string", "description" => "Cc address(es), comma-separated (optional)" }
            },
            "required" => %w[to subject body]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_email" then send_email(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_email(args)
      raw = base64url(mime_message(
        to: require_arg(args, "to"),
        subject: require_arg(args, "subject"),
        body: require_arg(args, "body"),
        cc: (args["cc"] || args[:cc]).to_s
      ))
      uri = build_uri(API_BASE, "/gmail/v1/users/me/messages/send")
      resp = ensure_ok!(post_json(uri, { "raw" => raw }, headers: auth_headers), "Gmail")
      { "ok" => true, "message" => parse_json(resp.body) }
    end

    # A minimal RFC 2822 message. Gmail wants the whole thing base64url-encoded
    # in the "raw" field.
    def mime_message(to:, subject:, body:, cc: "")
      lines = [ "To: #{to}" ]
      lines << "Cc: #{cc}" if cc.present?
      lines += [
        "Subject: #{subject}",
        "MIME-Version: 1.0",
        %(Content-Type: text/plain; charset="UTF-8"),
        "",
        body
      ]
      lines.join("\r\n")
    end

    # Standard base64 → URL-safe, unpadded (matches the codebase's pack("m0") idiom).
    def base64url(str)
      [ str ].pack("m0").tr("+/", "-_").delete("=")
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
