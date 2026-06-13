module Connectors
  # Effector-only provider: send an SMS via Kaleyra's v1 API (a CPaaS popular
  # across India / MENA). Auth is the `api-key` header (vaulted); the account
  # SID sits in the path and the Messages endpoint is form-encoded. Sending a
  # message to a citizen is :confirm — the AI prepares the send and a human
  # confirms before it goes out.
  class KaleyraProvider < HttpProvider
    DEFAULT_BASE = "https://api.kaleyra.io".freeze

    def self.descriptor
      Descriptor.new(
        key: "kaleyra", name: "Kaleyra (SMS/WhatsApp)", category: "Communications",
        auth: :none, config_fields: %w[sid sender base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send an SMS via Kaleyra.",
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

      sid = require_config("sid")
      uri = build_uri(base, "/v1/#{sid}/messages")
      form = { "to" => to, "sender" => require_config("sender"), "body" => text, "type" => "TXN" }
      resp = post_form(uri, form, headers: { "api-key" => require_secret("api_key") })
      ensure_ok!(resp, "Kaleyra")
      { "ok" => true, "message" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
