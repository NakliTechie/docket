module Connectors
  # Effector-only provider: post a message to a Google Chat space via an
  # incoming-webhook URL. Auth is unusual — there is NO Authorization header;
  # the webhook URL itself embeds a secret token (key + token query params), so
  # the whole URL lives in the credential vault. Notifying a pre-configured
  # internal space is mechanical and rights-neutral → :autonomous, like Slack
  # and Telegram. No inbound sync (syncs: false).
  class GoogleChatWebhookProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "googlechat_webhook", name: "Google Chat (incoming webhook)", category: "Communications",
        auth: :none, config_fields: [], credential_fields: %w[webhook_url], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "post_message", name: "Post Google Chat message",
          summary: "Post a message to the connected Google Chat space to notify staff.",
          params: {
            "type" => "object",
            "properties" => { "text" => { "type" => "string", "description" => "Message text" } },
            "required" => %w[text]
          },
          # Notifying a configured internal space is mechanical → runs unattended.
          effect: :write, decision_class: :autonomous
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "post_message" then post_message(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def post_message(args)
      text = (args["text"] || args[:text]).to_s.strip
      raise Connectors::Error, "text is required" if text.blank?

      uri = webhook_uri
      resp = post_json(uri, { "text" => text })
      ensure_ok!(resp, "Google Chat")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    # The secret webhook_url IS the endpoint. SSRF-guard it via build_uri and
    # require https (build_uri permits http, but Google Chat webhooks are https).
    def webhook_uri
      uri = build_uri(require_secret("webhook_url"))
      raise Connectors::Error, "webhook_url must be https" unless uri.is_a?(URI::HTTPS)
      uri
    end
  end
end
