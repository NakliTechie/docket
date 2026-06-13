module Connectors
  # Effector-only provider: trigger a self-hosted n8n workflow by POSTing a
  # JSON payload to its incoming-webhook URL. The URL embeds the workflow's
  # webhook id (and may carry a secret path component), so the whole URL is
  # the credential and lives in the vault — there is NO Authorization header.
  #
  # Sovereign fit: n8n is typically self-hosted on the operator's own network,
  # so build_uri's SSRF guard (which allows RFC1918 private ranges but blocks
  # loopback / link-local) lets an on-prem hook through while still refusing
  # the cloud-metadata vector. Triggering a workflow is a discretionary
  # outbound write whose downstream effects we can't see → :confirm (a human
  # approves before it fires, unless the operator auto-approves the action).
  class N8nWebhookProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "n8n_webhook", name: "n8n (webhook)", category: "Automation",
        auth: :none, config_fields: [], credential_fields: %w[webhook_url], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "trigger_workflow", name: "Trigger n8n workflow",
          summary: "POST a JSON payload to a self-hosted n8n webhook to run a workflow.",
          params: {
            "type" => "object",
            "properties" => {
              "payload" => { "type" => "object", "description" => "JSON body sent to the n8n webhook" }
            },
            "required" => %w[payload]
          },
          # Discretionary outbound write with unseen downstream effects → a
          # human confirms before the workflow fires.
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "trigger_workflow" then trigger_workflow(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def trigger_workflow(args)
      payload = args["payload"] || args[:payload]
      raise Connectors::Error, "payload must be an object" unless payload.is_a?(Hash)

      # The webhook_url secret IS the endpoint — no path, no auth header.
      uri = build_uri(require_secret("webhook_url"))
      resp = post_json(uri, payload)
      ensure_ok!(resp, "n8n")
      { "ok" => true, "result" => parse_json(resp.body) }
    end
  end
end
