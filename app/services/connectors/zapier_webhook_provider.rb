module Connectors
  # Effector-only provider: trigger a Zapier automation by POSTing a JSON
  # payload to a Zapier "catch hook" URL. The hook URL embeds a secret token,
  # so the whole URL IS the endpoint and lives in the credential vault — there
  # is no Authorization header. One Zap can fan out to ~9,000 downstream apps,
  # so the blast radius is unknown to docket; triggering external automation is
  # discretionary → :confirm (a human confirms before it takes effect). No
  # inbound sync (syncs: false).
  class ZapierWebhookProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "zapier_webhook", name: "Zapier (catch hook)", category: "Automation",
        auth: :none, config_fields: [], credential_fields: %w[hook_url], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "trigger_zap", name: "Trigger Zap",
          summary: "POST a JSON payload to a Zapier catch-hook to trigger an automation (bridges ~9,000 apps).",
          params: {
            "type" => "object",
            "properties" => {
              "payload" => { "type" => "object",
                             "description" => "Arbitrary JSON object posted as the request body to the Zap." }
            },
            "required" => %w[payload]
          },
          # Fires external automation of unknown reach → a human confirms first.
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "trigger_zap" then trigger_zap(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def trigger_zap(args)
      payload = args["payload"] || args[:payload]
      raise Connectors::Error, "payload is required" unless payload.is_a?(Hash)

      uri = hook_uri
      resp = post_json(uri, payload)
      ensure_ok!(resp, "Zapier")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    # The secret hook_url is the full endpoint. build_uri already SSRF-guards
    # and rejects non-http(s); we additionally require https for a hosted hook.
    def hook_uri
      uri = build_uri(require_secret("hook_url"))
      raise Connectors::Error, "hook_url must be https" unless uri.is_a?(URI::HTTPS)
      uri
    end
  end
end
