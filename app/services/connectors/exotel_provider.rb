module Connectors
  # Effector-only provider: send an SMS via Exotel's REST API (a CPaaS popular
  # across India). Auth is HTTP Basic with the API key as the user and the API
  # token as the password (both vaulted); the account SID sits in the path and
  # the Sms/send endpoint is form-encoded. Sending a message to a citizen is
  # :confirm — the AI prepares the send and a human confirms before it goes out.
  class ExotelProvider < HttpProvider
    DEFAULT_BASE = "https://api.exotel.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "exotel", name: "Exotel (SMS)", category: "Communications",
        auth: :none, config_fields: %w[account_sid from base_url],
        credential_fields: %w[api_key api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send an SMS via Exotel.",
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
      uri = build_uri(base, "/v1/Accounts/#{account_sid}/Sms/send.json")
      form = { "From" => require_config("from"), "To" => to, "Body" => text }
      resp = post_form(uri, form, headers: { "Authorization" => basic_auth(require_secret("api_key"), require_secret("api_token")) })
      ensure_ok!(resp, "Exotel")
      { "ok" => true, "message" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
