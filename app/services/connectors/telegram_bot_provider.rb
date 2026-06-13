module Connectors
  # Effector-only provider: post a message to a Telegram chat via the Bot API.
  # Auth is unusual — there is NO Authorization header; the bot token is part
  # of the URL path (`/bot<token>/sendMessage`), so it lives in the credential
  # vault. Notifying a pre-configured internal chat is mechanical and rights-
  # neutral → :autonomous, like Slack. No inbound sync (syncs: false).
  class TelegramBotProvider < HttpProvider
    DEFAULT_BASE = "https://api.telegram.org".freeze

    def self.descriptor
      Descriptor.new(
        key: "telegram_bot", name: "Telegram (bot)", category: "Communications",
        auth: :none, config_fields: %w[chat_id base_url], credential_fields: %w[bot_token], syncs: false
      )
    end

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

    private

    def send_message(args)
      text = (args["text"] || args[:text]).to_s.strip
      raise Connectors::Error, "text is required" if text.blank?

      chat_id = chat_id_for(args)
      base = connector.config_value("base_url").presence || DEFAULT_BASE
      uri = build_uri(base, "/bot#{require_secret('bot_token')}/sendMessage")
      resp = post_json(uri, { "chat_id" => chat_id, "text" => text })
      ensure_ok!(resp, "Telegram")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def chat_id_for(args)
      chat_id = (args["chat_id"] || args[:chat_id]).presence || connector.config_value("chat_id")
      chat_id = chat_id.to_s.strip
      raise Connectors::Error, "chat_id is required" if chat_id.blank?
      chat_id
    end
  end
end
