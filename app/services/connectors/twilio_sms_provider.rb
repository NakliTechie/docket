module Connectors
  # Effector-only provider: send an SMS via Twilio's REST API. Auth is HTTP
  # Basic with the Account SID as the user and the Auth Token as the password
  # (vaulted). The Messages endpoint is form-encoded and returns 201 Created on
  # a successful enqueue. Sending a message to a citizen is :confirm — the AI
  # prepares the send and a human confirms before it goes out.
  class TwilioSmsProvider < HttpProvider
    DEFAULT_BASE = "https://api.twilio.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "twilio_sms", name: "Twilio (SMS)", category: "Communications",
        auth: :none, config_fields: %w[account_sid from base_url],
        credential_fields: %w[auth_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send an SMS via Twilio.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient phone number in E.164 format" },
              "text" => { "type" => "string", "description" => "Message body" }
            },
            "required" => %w[to text]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_sms" then send_sms(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_sms(args)
      to   = (args["to"] || args[:to]).to_s.strip
      text = (args["text"] || args[:text]).to_s
      raise Connectors::Error, "to is required" if to.blank?
      raise Connectors::Error, "text is required" if text.blank?

      account_sid = require_config("account_sid")
      base = connector.config_value("base_url").presence || DEFAULT_BASE
      uri = build_uri(base, "/2010-04-01/Accounts/#{account_sid}/Messages.json")
      form = { "From" => require_config("from"), "To" => to, "Body" => text }
      resp = post_form(uri, form, headers: { "Authorization" => basic_auth(account_sid, require_secret("auth_token")) })
      ensure_ok!(resp, "Twilio")
      { "ok" => true, "message" => parse_json(resp.body) }
    end
  end
end
