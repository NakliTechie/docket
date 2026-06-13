module Connectors
  # Effector-only provider: post a message to a Microsoft Teams channel via an
  # incoming-webhook URL. Like the Slack incoming webhook, the secret IS the
  # full HTTPS endpoint — there is NO Authorization header; the unguessable
  # token rides in the URL itself, so it lives in the credential vault.
  # Notifying a configured channel is mechanical and rights-neutral →
  # :autonomous. No inbound sync (syncs: false).
  class MicrosoftTeamsWebhookProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "msteams_webhook", name: "Microsoft Teams (incoming webhook)", category: "Communications",
        auth: :none, config_fields: [], credential_fields: %w[webhook_url], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "post_message", name: "Post Teams message",
          summary: "Post a message to the connected Microsoft Teams channel to notify staff.",
          params: {
            "type" => "object",
            "properties" => { "text" => { "type" => "string", "description" => "Message text" } },
            "required" => %w[text]
          },
          # Notifying a configured channel is mechanical → runs unattended.
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
      ensure_ok!(resp, "Microsoft Teams")
      { "ok" => true, "posted" => text.truncate(80) }
    end

    # The secret webhook_url is the full endpoint. Build it through the SSRF
    # guard (no path), then require https — Teams webhooks are always https.
    def webhook_uri
      uri = build_uri(require_secret("webhook_url"))
      raise Connectors::Error, "webhook_url must be https" unless uri.is_a?(URI::HTTPS)
      uri
    end
  end
end
