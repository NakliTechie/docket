module Connectors
  # Effector-only provider: send an SMS or WhatsApp message to a customer via
  # Gupshup, a widely used CPaaS (strong in India). Auth is the `apikey`
  # header (vaulted); the registered source/sender is a config value. The
  # /sm/api/v1/msg endpoint is form-encoded. Sending a message to a customer
  # is :confirm — the AI prepares the send and a human confirms before it goes
  # out.
  class GupshupProvider < HttpProvider
    DEFAULT_BASE = "https://api.gupshup.io".freeze
    DEFAULT_CHANNEL = "sms".freeze

    def self.descriptor
      Descriptor.new(
        key: "gupshup", name: "Gupshup (messaging)", category: "Communications",
        auth: :none, config_fields: %w[source base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_message", name: "Send message",
          summary: "Send an SMS/WhatsApp message via Gupshup.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient phone number (E.164 / national format)" },
              "text" => { "type" => "string", "description" => "Message body text" },
              "channel" => { "type" => "string", "description" => "Delivery channel (default 'sms')" }
            },
            "required" => %w[to text]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_message" then send_message(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_message(args)
      to   = (args["to"] || args[:to]).to_s.strip
      text = (args["text"] || args[:text]).to_s
      raise Connectors::Error, "to is required" if to.blank?
      raise Connectors::Error, "text is required" if text.blank?

      channel = (args["channel"] || args[:channel]).to_s.strip.presence || DEFAULT_CHANNEL
      uri = build_uri(base, "/sm/api/v1/msg")
      form = {
        "channel" => channel,
        "source" => require_config("source"),
        "destination" => to,
        "message" => text
      }
      resp = post_form(uri, form, headers: { "apikey" => require_secret("api_key") })
      ensure_ok!(resp, "Gupshup")
      { "ok" => true, "message" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
