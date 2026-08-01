module Connectors
  # Effector-only provider: send a templated SMS to a customer via MSG91 (the
  # dominant India CPaaS). Auth is the `authkey` header (vaulted). Customer-
  # facing comms default to :confirm — a human reviews before it goes out
  # (the connector can auto-approve it if the operator trusts the template).
  class Msg91Provider < HttpProvider
    CHANNEL = "sms".freeze

    def self.descriptor
      Descriptor.new(
        key: "msg91", name: "MSG91 (SMS / WhatsApp)", category: "Communications",
        auth: :none, config_fields: %w[sender_id template_id base_url],
        credential_fields: %w[authkey], syncs: false
      )
    end

    # Inbound: parse MSG91 incoming-SMS webhooks into cases.
    def self.ingests? = true

    # MSG91 has no cryptographic webhook signature, so inbound is authenticated
    # with a shared secret: the connector's webhook_secret, supplied by MSG91 as
    # the X-Webhook-Token header (preferred) or a ?token= query param. The
    # operator configures the webhook URL/header with that secret. Fail-closed.
    def inbound_authentic?(request)
      secret = connector.webhook_secret.to_s
      provided = request.headers["X-Webhook-Token"].to_s.presence || request.query_parameters["token"].to_s
      return false if secret.blank? || provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided, secret)
    end

    # MSG91 inbound JSON → one normalized message. Field names vary across MSG91
    # webhook versions, so accept the common aliases; a payload with no sender
    # (e.g. a delivery report) yields nothing.
    def ingest(payload)
      return [] unless payload.is_a?(Hash) # a non-object JSON body (array/scalar) is not a message

      sender = (payload["sender"] || payload["from"] || payload["mobile"]).to_s
      return [] if sender.blank?

      [ {
        sender: { name: sender, phone: sender, external_id: sender },
        external_thread_id: sender,
        body: (payload["content"] || payload["message"] || payload["text"] || payload["body"]).to_s,
        channel: CHANNEL,
        external_message_id: (payload["message_id"] || payload["id"] || payload["requestId"]).to_s.presence
      } ]
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send a DLT-templated SMS to a customer's mobile number via MSG91.",
          params: {
            "type" => "object",
            "properties" => {
              "mobile" => { "type" => "string", "description" => "Recipient mobile (E.164 or 10-digit)" },
              "variables" => { "type" => "object", "description" => "Template variable values" }
            },
            "required" => %w[mobile]
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

    # The agent-facing path: Connectors::Invoke has already authorized,
    # budgeted and (for :confirm) human-approved this send; the actual MSG91
    # call is delegated to the shared Comms::SmsGateway.
    def send_sms(args)
      Comms::SmsGateway.new(connector).deliver(
        mobile: (args["mobile"] || args[:mobile]),
        variables: variables(args)
      )
    rescue Comms::SmsGateway::Error => e
      raise Connectors::Error, e.message
    end

    def variables(args)
      vars = args["variables"] || args[:variables]
      vars.is_a?(Hash) ? vars : {}
    end
  end
end
