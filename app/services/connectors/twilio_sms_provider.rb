module Connectors
  # Effector-only provider: send an SMS via Twilio's REST API. Auth is HTTP
  # Basic with the Account SID as the user and the Auth Token as the password
  # (vaulted). The Messages endpoint is form-encoded and returns 201 Created on
  # a successful enqueue. Sending a message to a customer is :confirm — the AI
  # prepares the send and a human confirms before it goes out.
  class TwilioSmsProvider < HttpProvider
    DEFAULT_BASE = "https://api.twilio.com".freeze
    CHANNEL = "sms".freeze

    def self.descriptor
      Descriptor.new(
        key: "twilio_sms", name: "Twilio (SMS)", category: "Communications",
        auth: :none, config_fields: %w[account_sid from base_url],
        # auth_token both sends (HTTP Basic) AND verifies inbound webhook
        # signatures (X-Twilio-Signature) — no extra credential for inbound.
        credential_fields: %w[auth_token], syncs: false
      )
    end

    # Inbound: parse Twilio's incoming-SMS webhooks into cases.
    def self.ingests? = true

    # Twilio posts inbound SMS as application/x-www-form-urlencoded, not JSON.
    def inbound_payload(request)
      request.request_parameters
    end

    # Twilio signs each webhook with X-Twilio-Signature =
    # base64(HMAC-SHA1(auth_token, full_url + sorted(param key+value))).
    # Fail-closed when the token or header is absent (drop unverifiable inbound
    # rather than ingest a forgery).
    def inbound_authentic?(request)
      token = connector.secret("auth_token").to_s
      provided = request.headers["X-Twilio-Signature"].to_s
      return false if token.blank? || provided.blank?

      data = request.original_url + request.request_parameters.sort.map { |key, value| "#{key}#{value}" }.join
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", token, data))
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    # Twilio inbound form → one normalized message (delivery-status callbacks,
    # which carry no From/Body, yield nothing).
    def ingest(payload)
      from = payload["From"].to_s
      return [] if from.blank?

      [ {
        sender: { name: from, phone: from, external_id: from },
        external_thread_id: from,
        body: payload["Body"].to_s,
        channel: CHANNEL,
        external_message_id: (payload["MessageSid"] || payload["SmsSid"]).to_s.presence
      } ]
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send an SMS via Twilio.",
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

      account_sid = require_config("account_sid")
      base = connector.config_value("base_url").presence || DEFAULT_BASE
      uri = build_uri(base, "/2010-04-01/Accounts/#{account_sid}/Messages.json")
      form = { "From" => require_config("from"), "To" => to, "Body" => text }
      resp = post_form(uri, form, headers: { "Authorization" => basic_auth(account_sid, require_secret("auth_token")) })
      ensure_ok!(resp, "Twilio")
      { "ok" => true, "message" => parse_json(resp.body) }
    end
  end
end
