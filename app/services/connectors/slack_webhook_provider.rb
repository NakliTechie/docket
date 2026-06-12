module Connectors
  # Effector-only provider: post a message to Slack via an incoming-webhook
  # URL. The URL embeds a secret token, so it lives in the credential vault.
  # No inbound sync — the agent uses it to notify staff. The easiest real
  # provider: one secret, one autonomous action, a public HTTPS endpoint.
  class SlackWebhookProvider < Provider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

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

    # Effector-only: never pulls records.
    def fetch
      []
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
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      req.body = JSON.generate(text: text)
      response = request(req, uri)
      unless response.code.to_i.between?(200, 299)
        raise Connectors::Error, "Slack returned HTTP #{response.code}"
      end
      { "ok" => true, "posted" => text.truncate(80) }
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
      raise Connectors::Error, "slack post failed: #{e.class}: #{e.message}"
    end

    def webhook_uri
      url = connector.secret("webhook_url").to_s
      raise Connectors::Error, "webhook_url is required" if url.blank?
      uri = URI.parse(url)
      raise Connectors::Error, "webhook_url must be https" unless uri.is_a?(URI::HTTPS)
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Connectors::Error, "endpoint blocked: #{reason}"
      end
      uri
    rescue URI::InvalidURIError
      raise Connectors::Error, "webhook_url is not a valid URL"
    end

    def request(req, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(req)
    end
  end
end
