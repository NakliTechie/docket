module Connectors
  # Effector-only provider: post a message to Slack via an incoming-webhook
  # URL. The URL embeds a secret token, so it lives in the credential vault.
  # No inbound sync — the agent uses it to notify staff. The easiest real
  # provider: one secret, one autonomous action, a public HTTPS endpoint.
  class SlackWebhookProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "slack_webhook", name: "Slack (incoming webhook)", category: "Communications",
        auth: :none, config_fields: [], credential_fields: %w[webhook_url], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "post_message", name: "Post Slack message",
          summary: "Post a short message to the connected Slack channel to notify staff.",
          params: {
            "type" => "object",
            "properties" => { "text" => { "type" => "string", "description" => "Message text" } },
            "required" => %w[text]
          },
          # Notifying staff is mechanical and rights-neutral → runs unattended.
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

      uri = build_uri(require_secret("webhook_url"))
      # The webhook URL embeds a secret token — never send it over cleartext.
      raise Connectors::Error, "webhook_url must be https" unless uri.scheme == "https"
      response = post_json(uri, { text: text })
      ensure_ok!(response, "Slack")
      { "ok" => true, "posted" => text.truncate(80) }
    end
  end
end
