module Connectors
  # Effector-only provider: post a message to a Telegram chat via the Bot API.
  # Auth is unusual — there is NO Authorization header; the bot token is part
  # of the URL path (`/bot<token>/sendMessage`), so it lives in the credential
  # vault. Notifying a pre-configured internal chat is mechanical and rights-
  # neutral → :autonomous, like Slack. No inbound sync (syncs: false).
  class TelegramBotProvider < HttpProvider
    DEFAULT_BASE = "https://api.telegram.org".freeze
    CHANNEL = "telegram".freeze

    def self.descriptor
      Descriptor.new(
        key: "telegram_bot", name: "Telegram (bot)", category: "Communications",
        auth: :none, config_fields: %w[chat_id base_url], credential_fields: %w[bot_token], syncs: false
      )
    end

    # Inbound: parse Telegram bot updates into cases.
    def self.ingests? = true

    def self.actions
      [
        Action.new(
          key: "send_message", name: "Send Telegram message",
          summary: "Post a message to the connected Telegram chat to notify staff.",
          params: {
            "type" => "object",
            "properties" => {
              "text" => { "type" => "string", "description" => "Message text" },
              "chat_id" => { "type" => "string",
                             "description" => "Target chat id; defaults to the connector's configured chat_id" }
            },
            "required" => %w[text]
          },
          # Notifying a configured internal chat is mechanical → runs unattended.
          effect: :write, decision_class: :autonomous
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_message" then send_message(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    # Telegram echoes the secret token set on setWebhook in this header; we use
    # the connector's webhook_secret as that token. Fail-closed on a mismatch.
    def inbound_authentic?(request)
      provided = request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s
      return false if provided.blank?
      ActiveSupport::SecurityUtils.secure_compare(provided, connector.webhook_secret.to_s)
    end

    # A bot update → one inbound message (or none, for non-message updates).
    # chat.id is the conversation/thread key; from.id keys the contact.
    def ingest(payload)
      msg = payload["message"] || payload["edited_message"]
      return [] unless msg.is_a?(Hash)

      from = msg["from"] || {}
      chat_id = msg.dig("chat", "id").to_s
      sender_id = from["id"].to_s
      body = (msg["text"] || msg["caption"]).to_s
      [ {
        sender: { name: telegram_name(from).presence || sender_id, phone: nil, external_id: sender_id },
        external_thread_id: chat_id.presence || sender_id,
        body: body.presence || "[message]",
        channel: CHANNEL,
        external_message_id: msg["message_id"].to_s.presence
      } ]
    end

    private

    def telegram_name(from)
      [ from["first_name"], from["last_name"] ].compact_blank.join(" ").presence || from["username"].to_s
    end

    def send_message(args)
      text = (args["text"] || args[:text]).to_s.strip
      raise Connectors::Error, "text is required" if text.blank?

      chat_id = chat_id_for(args)
      base = connector.config_value("base_url").presence || DEFAULT_BASE
      uri = build_uri(base, "/bot#{require_secret('bot_token')}/sendMessage")
      resp = post_json(uri, { "chat_id" => chat_id, "text" => text })
      ensure_ok!(resp, "Telegram")
      body = parse_json(resp.body)
      # Surface the sent message id so the reply-out loop can record it (L5).
      { "ok" => true, "message_id" => (body.dig("result", "message_id") if body.is_a?(Hash)), "result" => body }
    end

    def chat_id_for(args)
      chat_id = (args["chat_id"] || args[:chat_id]).presence || connector.config_value("chat_id")
      chat_id = chat_id.to_s.strip
      raise Connectors::Error, "chat_id is required" if chat_id.blank?
      chat_id
    end
  end
end
