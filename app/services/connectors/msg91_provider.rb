module Connectors
  # Effector-only provider: send a templated SMS to a citizen via MSG91 (the
  # dominant India CPaaS). Auth is the `authkey` header (vaulted). Citizen-
  # facing comms default to :confirm — a human reviews before it goes out
  # (the connector can auto-approve it if the operator trusts the template).
  class Msg91Provider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "msg91", name: "MSG91 (SMS / WhatsApp)", category: "Communications",
        auth: :none, config_fields: %w[sender_id template_id base_url],
        credential_fields: %w[authkey], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send a DLT-templated SMS to a citizen's mobile number via MSG91.",
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
