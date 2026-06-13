module Connectors
  # Effector-only provider: send an SMS via Sinch's XMS (SMS) REST API. Auth is
  # a Bearer API token (vaulted). The sender (from) and the service plan id are
  # operator config; the service_plan_id is interpolated into the batches path.
  # Sinch's batch endpoint takes a JSON body whose `to` is an ARRAY of
  # recipients and returns 201 Created on a successful enqueue. Sending a
  # message to a citizen is rights-touching comms → :confirm (the AI prepares
  # the send and a human confirms before it goes out).
  class SinchProvider < HttpProvider
    DEFAULT_BASE = "https://sms.api.sinch.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "sinch", name: "Sinch (SMS)", category: "Communications",
        auth: :none, config_fields: %w[service_plan_id from base_url],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send an SMS via Sinch.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient phone number in E.164 format" },
              "text" => { "type" => "string", "description" => "Message body" }
            },
            "required" => %w[to text]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_sms" then send_sms(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_sms(args)
      to   = (args["to"] || args[:to]).to_s.strip
      text = (args["text"] || args[:text]).to_s
      raise Connectors::Error, "to is required" if to.blank?
      raise Connectors::Error, "text is required" if text.blank?

      service_plan_id = require_config("service_plan_id")
      uri = build_uri(base, "/xms/v1/#{service_plan_id}/batches")
      payload = { "from" => require_config("from"), "to" => [ to ], "body" => text }
      resp = post_json(uri, payload, headers: { "Authorization" => bearer(require_secret("api_token")) })
      ensure_ok!(resp, "Sinch")
      { "ok" => true, "to" => to, "message" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
