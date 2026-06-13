module Connectors
  # Effector-only provider: send an SMS via Plivo's REST API. Auth is HTTP
  # Basic with the Auth ID as the user and the Auth Token as the password
  # (vaulted). The Message endpoint takes a JSON body { src, dst, text } and
  # returns 202 Accepted on a successful enqueue. Sending a message to a
  # citizen is :confirm — the AI prepares the send and a human confirms
  # before it goes out.
  class PlivoProvider < HttpProvider
    DEFAULT_BASE = "https://api.plivo.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "plivo", name: "Plivo (SMS)", category: "Communications",
        auth: :none, config_fields: %w[auth_id from base_url],
        credential_fields: %w[auth_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send an SMS via Plivo.",
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

      auth_id = require_config("auth_id")
      uri  = build_uri(base, "/v1/Account/#{auth_id}/Message/")
      body = { "src" => require_config("from"), "dst" => to, "text" => text }
      resp = post_json(uri, body, headers: { "Authorization" => basic_auth(auth_id, require_secret("auth_token")) })
      ensure_ok!(resp, "Plivo")
      { "ok" => true, "message" => parse_json(resp.body) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
