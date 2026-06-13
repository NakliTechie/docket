module Connectors
  # Effector-only provider: send a transactional email via SendGrid's v3 API.
  # Auth is a Bearer API key (vaulted). The sender address is operator config
  # (from_email), so the agent only supplies recipient/subject/body. Emailing
  # a citizen is rights-touching comms → :confirm (a human reviews before it
  # goes out). SendGrid signals success with HTTP 202; ensure_ok! accepts any
  # 2xx, which covers it.
  class SendgridProvider < HttpProvider
    DEFAULT_BASE = "https://api.sendgrid.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "sendgrid", name: "SendGrid (email)", category: "Communications",
        auth: :none, config_fields: %w[from_email base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_email", name: "Send email",
          summary: "Send a transactional email via SendGrid.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient email address" },
              "subject" => { "type" => "string", "description" => "Email subject line" },
              "body" => { "type" => "string", "description" => "Plain-text email body" }
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
      to = (args["to"] || args[:to]).to_s.strip
      subject = (args["subject"] || args[:subject]).to_s.strip
      body = (args["body"] || args[:body]).to_s
      raise Connectors::Error, "to is required" if to.blank?
      raise Connectors::Error, "subject is required" if subject.blank?
      raise Connectors::Error, "body is required" if body.blank?

      from_email = require_config("from_email")
      uri = build_uri(base, "/v3/mail/send")
      payload = {
        personalizations: [ { to: [ { email: to } ] } ],
        from: { email: from_email },
        subject: subject,
        content: [ { type: "text/plain", value: body } ]
      }
      response = post_json(uri, payload, headers: { "Authorization" => bearer(require_secret("api_key")) })
      ensure_ok!(response, "SendGrid")
      { "ok" => true, "to" => to, "subject" => subject, "status" => response.code.to_i }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
