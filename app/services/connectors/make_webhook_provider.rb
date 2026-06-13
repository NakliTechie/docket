module Connectors
  # Effector-only provider: trigger a Make (Integromat) scenario by POSTing a
  # JSON payload to its custom-webhook URL. Auth is unusual — there is NO
  # Authorization header; the secret IS the endpoint. The full hook_url embeds
  # the scenario's opaque token, so it lives in the credential vault and the
  # request URI is built straight from it.
  #
  # Triggering a scenario hands control to an opaque downstream automation whose
  # blast radius the agent can't see, so unlike a plain staff notification this
  # is NOT mechanical/rights-neutral → :confirm (a human confirms before it
  # fires). No inbound sync (syncs: false).
  class MakeWebhookProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "make_webhook", name: "Make (webhook)", category: "Automation",
        auth: :none, config_fields: [], credential_fields: %w[hook_url], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "trigger_scenario", name: "Trigger Make scenario",
          summary: "POST a JSON payload to a Make custom webhook to run a scenario.",
          params: {
            "type" => "object",
            "properties" => {
              "payload" => { "type" => "object",
                             "description" => "JSON object passed to the Make scenario as its trigger bundle" }
            },
            "required" => %w[payload]
          },
          # Hands off to an opaque downstream automation → a human confirms first.
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "trigger_scenario" then trigger_scenario(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def trigger_scenario(args)
      payload = args["payload"] || args[:payload]
      raise Connectors::Error, "payload is required" unless payload.is_a?(Hash)

      # The secret hook_url IS the endpoint — no path, no auth header.
      uri = build_uri(require_secret("hook_url"))
      resp = post_json(uri, payload)
      ensure_ok!(resp, "Make")
      { "ok" => true, "result" => parse_json(resp.body) }
    end
  end
end
