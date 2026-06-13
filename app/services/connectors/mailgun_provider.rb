module Connectors
  # Effector-only Mailgun provider: send a transactional email via the
  # Messages API (POST /v3/{domain}/messages). Auth is HTTP Basic where the
  # username is the literal "api" and the password is the vaulted api_key, per
  # Mailgun's convention. The sending domain and from-address are operator
  # config, so the agent only supplies recipient/subject/body. The body is
  # form-encoded (Mailgun expects application/x-www-form-urlencoded), so we use
  # post_form. EU operators point base_url at https://api.eu.mailgun.net.
  # Emailing a citizen is rights-touching comms → :confirm (a human reviews
  # before it goes out).
  class MailgunProvider < HttpProvider
    DEFAULT_BASE = "https://api.mailgun.net".freeze

    def self.descriptor
      Descriptor.new(
        key: "mailgun", name: "Mailgun (email)", category: "Communications",
        auth: :none, config_fields: %w[domain from base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_email", name: "Send email",
          summary: "Send an email via Mailgun.",
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

      uri = build_uri(base, "/v3/#{require_config('domain')}/messages")
      form = {
        "from" => require_config("from"),
        "to" => to,
        "subject" => subject,
        "text" => body
      }
      resp = post_form(uri, form, headers: auth_headers)
      ensure_ok!(resp, "Mailgun")
      { "ok" => true, "to" => to, "subject" => subject, "result" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def auth_headers
      { "Authorization" => basic_auth("api", require_secret("api_key")) }
    end
  end
end
