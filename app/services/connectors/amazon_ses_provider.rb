module Connectors
  # Amazon SES (v2) — send transactional email, SigV4-signed (service "ses").
  # Static IAM credentials + region; the verified sending identity is the
  # configured from_email. Sending is :confirm. Effector-only.
  class AmazonSesProvider < AwsProvider
    def self.descriptor
      Descriptor.new(
        key: "amazon_ses", name: "Amazon SES", category: "Communications",
        auth: :none, config_fields: %w[region from_email],
        credential_fields: %w[access_key_id secret_access_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_email", name: "Send email",
          summary: "Send a transactional email via Amazon SES.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient email address" },
              "subject" => { "type" => "string", "description" => "Subject line" },
              "body" => { "type" => "string", "description" => "Plain-text body" }
            },
            "required" => %w[to subject body]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_email" then send_email(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_email(args)
      payload = JSON.generate(
        "FromEmailAddress" => require_config("from_email"),
        "Destination" => { "ToAddresses" => [ require_arg(args, "to") ] },
        "Content" => {
          "Simple" => {
            "Subject" => { "Data" => require_arg(args, "subject") },
            "Body" => { "Text" => { "Data" => require_arg(args, "body") } }
          }
        }
      )
      uri = build_uri("https://email.#{require_config('region')}.amazonaws.com", "/v2/email/outbound-emails")
      resp = signed_request("POST", uri, service: "ses", payload: payload,
                            unsigned_headers: { "Content-Type" => "application/json" })
      ensure_ok!(resp, "Amazon SES")
      { "ok" => true, "result" => parse_json(resp.body) }
    end
  end
end
