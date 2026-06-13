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

    CHANNEL = "whatsapp".freeze

    def self.descriptor
      Descriptor.new(
        key: "whatsapp_cloud", name: "WhatsApp Business (Cloud API)", category: "Communications",
        auth: :none, config_fields: %w[phone_number_id base_url],
        # access_token sends; app_secret verifies inbound webhook signatures
        # (optional — only inbound needs it). The connector's webhook_secret
        # doubles as the Meta verify-token for the GET handshake.
        credential_fields: %w[access_token app_secret],
        required_credential_fields: %w[access_token], syncs: false
      )
    end

    # Inbound: parse WhatsApp Cloud "messages" webhooks into cases.
    def self.ingests? = true

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

    # Meta signs every webhook with X-Hub-Signature-256 = HMAC-SHA256(app_secret,
    # raw_body). Fail-closed when no app_secret is configured (better to drop
    # unverifiable inbound than to ingest a forgery).
    def inbound_authentic?(request)
      secret = connector.secret("app_secret").to_s
      return false if secret.blank?
      provided = request.headers["X-Hub-Signature-256"].to_s
      return false if provided.blank?
      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)}"
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    # GET verification handshake: echo hub.challenge iff the verify token matches
    # the connector's webhook_secret (which the operator sets as Meta's token).
    def verification_challenge(params)
      return nil unless params["hub.mode"].to_s == "subscribe"
      token = params["hub.verify_token"].to_s
      return nil if token.blank? || connector.webhook_secret.to_s.blank?
      return nil unless ActiveSupport::SecurityUtils.secure_compare(token, connector.webhook_secret.to_s)
      params["hub.challenge"].to_s.presence
    end

    # entry[].changes[].value.messages[] → normalized inbound messages. Status
    # receipts (value.statuses) carry no messages and yield [].
    def ingest(payload)
      values = Array(payload["entry"]).flat_map { |e| Array(e["changes"]) }.filter_map { |c| c["value"] }
      values.flat_map do |value|
        names = Array(value["contacts"]).to_h { |c| [ c["wa_id"].to_s, c.dig("profile", "name") ] }
        Array(value["messages"]).map do |msg|
          from = msg["from"].to_s
          {
            sender: { name: names[from].presence || from, phone: from, external_id: from },
            external_thread_id: from,
            body: message_body(msg),
            channel: CHANNEL,
            external_message_id: msg["id"].to_s.presence
          }
        end
      end
    end

    private

    # Text bodies pass through; non-text messages (image, audio, location…) get
    # a typed marker so the case still threads and a human can follow up.
    def message_body(msg)
      type = msg["type"].to_s
      return msg.dig("text", "body").to_s if type == "text"
      caption = msg.dig(type, "caption").to_s
      caption.presence || "[#{type.presence || 'message'}]"
    end

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
