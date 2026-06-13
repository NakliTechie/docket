module Connectors
  # Effector-only provider: send a WhatsApp message to a customer via Gupshup,
  # a widely used CPaaS (strong in India). Auth is the `apikey` header (vaulted);
  # the registered WhatsApp source number and the Gupshup app name (`src.name`)
  # are config. Uses the /wa/api/v1/msg endpoint — the legacy /sm endpoint was
  # end-of-lifed 2025-06-30. Sending a message to a customer is :confirm — the
  # AI prepares the send and a human confirms before it goes out.
  class GupshupProvider < HttpProvider
    DEFAULT_BASE = "https://api.gupshup.io".freeze

    def self.descriptor
      Descriptor.new(
        key: "gupshup", name: "Gupshup (WhatsApp)", category: "Communications",
        auth: :none, config_fields: %w[source app_name base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_message", name: "Send WhatsApp message",
          summary: "Send a WhatsApp message to a customer via Gupshup.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient phone number (E.164 / national format)" },
              "text" => { "type" => "string", "description" => "Message body text" }
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

      uri = build_uri(base, "/wa/api/v1/msg")
      form = {
        "channel" => "whatsapp",
        "source" => require_config("source"),
        "src.name" => require_config("app_name"),
        "destination" => to,
        "message" => { "type" => "text", "text" => text }.to_json
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
