module Connectors
  # Effector-only provider: send WhatsApp messages to a customer via the Meta
  # WhatsApp Business Cloud API (Graph API). Auth is a Bearer access_token
  # (vaulted) in the Authorization header; the phone_number_id is a config
  # value. Both sends are citizen-facing comms → :confirm (a human reviews the
  # outbound message before it goes out). Free-form text is only valid inside
  # the 24h customer-service window; a pre-approved template is the only way to
  # message outside it.
  class WhatsappCloudProvider < HttpProvider
    DEFAULT_BASE = "https://graph.facebook.com/v21.0".freeze
    DEFAULT_LANGUAGE = "en_US".freeze

    def self.descriptor
      Descriptor.new(
        key: "whatsapp_cloud", name: "WhatsApp Business (Cloud API)", category: "Communications",
        auth: :none, config_fields: %w[phone_number_id base_url],
        credential_fields: %w[access_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_text_message", name: "Send WhatsApp message",
          summary: "Send a free-form text WhatsApp message to a customer (valid only inside a 24h service window).",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient phone number in E.164 (e.g. 15551234567)" },
              "text" => { "type" => "string", "description" => "Message body text" }
            },
            "required" => %w[to text]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "send_template_message", name: "Send WhatsApp template",
          summary: "Send a pre-approved WhatsApp template message (the only way to message outside the 24h window).",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient phone number in E.164 (e.g. 15551234567)" },
              "template_name" => { "type" => "string", "description" => "Name of the approved message template" },
              "language" => { "type" => "string", "description" => "Template language/locale code (default en_US)" }
            },
            "required" => %w[to template_name]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_text_message"     then send_text_message(args)
      when "send_template_message" then send_template_message(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_text_message(args)
      to   = present!(args, "to")
      text = present!(args, "text")
      resp = post_json(messages_uri, {
        messaging_product: "whatsapp",
        recipient_type: "individual",
        to: to,
        type: "text",
        text: { preview_url: false, body: text }
      }, headers: auth_headers)
      ensure_ok!(resp, "WhatsApp Cloud")
      result(resp)
    end

    def send_template_message(args)
      to       = present!(args, "to")
      template = present!(args, "template_name")
      language = (args["language"] || args[:language]).to_s.strip.presence || DEFAULT_LANGUAGE
      resp = post_json(messages_uri, {
        messaging_product: "whatsapp",
        to: to,
        type: "template",
        template: { name: template, language: { code: language } }
      }, headers: auth_headers)
      ensure_ok!(resp, "WhatsApp Cloud")
      result(resp)
    end

    def result(resp)
      body = parse_json(resp.body)
      message_id = body.is_a?(Hash) ? body.dig("messages", 0, "id") : nil
      { "ok" => true, "message_id" => message_id, "result" => body }
    end

    def messages_uri
      build_uri(base, "/#{require_config('phone_number_id')}/messages")
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
    end

    def present!(args, key)
      value = (args[key] || args[key.to_sym]).to_s.strip
      raise Connectors::Error, "#{key} is required" if value.blank?
      value
    end
  end
end
