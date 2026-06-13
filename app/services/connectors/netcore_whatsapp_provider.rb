module Connectors
  # Netcore Cloud WhatsApp (CPaaS WA API v2). Static auth-key credential, Bearer
  # header. Sends POST to cpaaswa.netcorecloud.net/api/v2/message/nc. Two sends,
  # both :confirm: a pre-approved template message and a free-form text reply
  # (only valid inside the 24-hour customer-service window). Phone numbers carry
  # the country code with no '+', e.g. 919869566055. Effector-only. Host/path +
  # body confirmed against Netcore's official api-summary (channels §2).
  class NetcoreWhatsappProvider < HttpProvider
    DEFAULT_BASE = "https://cpaaswa.netcorecloud.net/api/v2".freeze

    def self.descriptor
      Descriptor.new(
        key: "netcore_whatsapp", name: "Netcore WhatsApp", category: "Communications",
        auth: :none, config_fields: %w[source_id base_url],
        credential_fields: %w[auth_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_whatsapp", name: "Send WhatsApp template",
          summary: "Send a pre-approved WhatsApp template message via Netcore.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient number with country code, no '+' (e.g. 919869566055)" },
              "template_name" => { "type" => "string", "description" => "Approved template name" },
              "variables" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Template variable values, in order" },
              "language" => { "type" => "string", "description" => "Template locale (default en)" }
            },
            "required" => %w[to template_name]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "send_whatsapp_text", name: "Send WhatsApp text",
          summary: "Send a free-form WhatsApp text (only valid in the 24-hour service window).",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient number with country code, no '+'" },
              "text" => { "type" => "string", "description" => "Message text" }
            },
            "required" => %w[to text]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_whatsapp"      then send_template(args)
      when "send_whatsapp_text" then send_text(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_template(args)
      language = (args["language"] || args[:language]).to_s.strip.presence || "en"
      variables = args["variables"] || args[:variables] || []
      raise Connectors::Error, "variables must be an array" unless variables.is_a?(Array)

      message = base_message(require_arg(args, "to")).merge(
        "message_type" => "template",
        "type_template" => [ {
          "name" => require_arg(args, "template_name"),
          "attributes" => variables.map(&:to_s),
          "language" => { "locale" => language, "policy" => "deterministic" }
        } ]
      )
      send_message(message)
    end

    def send_text(args)
      message = base_message(require_arg(args, "to")).merge(
        "message_type" => "text",
        "type_text" => [ { "preview_url" => false, "content" => require_arg(args, "text") } ]
      )
      send_message(message)
    end

    def base_message(recipient)
      {
        "recipient_whatsapp" => recipient,
        "recipient_type" => "individual",
        "source" => require_config("source_id")
      }
    end

    def send_message(message)
      uri = build_uri(base, "/message/nc")
      headers = { "Authorization" => bearer(require_secret("auth_key")) }
      resp = ensure_ok!(post_json(uri, { "message" => [ message ] }, headers: headers), "Netcore WhatsApp")
      body = parse_json(resp.body)
      { "ok" => true, "id" => (body.is_a?(Hash) ? body.dig("data", "id") : nil), "result" => body }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
