module Connectors
  # Netcore Cloud SMS, via the CPaaS Deflector multi-channel send. Static
  # API-key credential. Sending is :confirm. India TRAI-DLT applies: the send
  # needs a DLT-approved template (dlt_template_id) + a registered sender_id, and
  # the text must match the approved template exactly. Effector-only.
  #
  # ⚠️ UNVERIFIED ENDPOINT (see plan/netcore-research-2026-06-13.md): Netcore's
  # standalone-SMS host/method/field-names could not be extracted from the
  # client-rendered docs. This implements the confirmed Deflector send contract
  # as the working assumption; the auth header (api-key vs api_key) is tried both
  # ways (one 401 retry). Settle with one authenticated live call before relying
  # on it in production, then doc-verify like the rest of the catalogue.
  class NetcoreSmsProvider < HttpProvider
    DEFAULT_BASE = "https://cpass-deflector.netcorecloud.net".freeze

    def self.descriptor
      Descriptor.new(
        key: "netcore_sms", name: "Netcore SMS", category: "Communications",
        auth: :none, config_fields: %w[sender_id feed_id dlt_template_id base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send a DLT-compliant SMS via Netcore.",
          params: {
            "type" => "object",
            "properties" => {
              "mobile" => { "type" => "string", "description" => "Recipient mobile (with country code)" },
              "text" => { "type" => "string", "description" => "Message text — must match the approved DLT template" }
            },
            "required" => %w[mobile text]
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
      body = {
        "to" => [ { "phoneNumber" => require_arg(args, "mobile") } ],
        "sms" => { "From" => require_config("sender_id"), "Text" => require_arg(args, "text") },
        "flow" => [ [ { "channel" => "SMS" } ] ]
      }

      uri = build_uri(base, "/messages/send")
      resp = post_json(uri, body, headers: { "api-key" => require_secret("api_key") })
      resp = post_json(uri, body, headers: { "api_key" => require_secret("api_key") }) if resp.code.to_i == 401
      ensure_ok!(resp, "Netcore SMS")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
