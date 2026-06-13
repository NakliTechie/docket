module Connectors
  # Netcore Cloud transactional Email (Pepipost lineage), v6 API. Static API-key
  # credential. Sending is :confirm — citizen/customer-facing comms get a human
  # review. Effector-only. Per-channel decomposition (email/SMS/WhatsApp are
  # separate providers) matches the catalogue convention and Netcore's three
  # distinct hosts + auth schemes. See plan/netcore-research-2026-06-13.md.
  #
  # Auth wrinkle settled at runtime: Netcore's own V6 docs disagree on the header
  # (quick-start says `Authorization: x-api-key <key>`, the OpenAPI says plain
  # bearer). We send x-api-key and transparently retry as bearer on a 401 — so
  # whichever the account expects, one call succeeds.
  class NetcoreEmailProvider < HttpProvider
    DEFAULT_BASE = "https://emailapi.netcorecloud.net/v6".freeze

    def self.descriptor
      Descriptor.new(
        key: "netcore_email", name: "Netcore Email", category: "Communications",
        auth: :none, config_fields: %w[from_email from_name base_url],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_email", name: "Send email",
          summary: "Send a transactional email via Netcore.",
          params: {
            "type" => "object",
            "properties" => {
              "to" => { "type" => "string", "description" => "Recipient email address" },
              "to_name" => { "type" => "string", "description" => "Recipient name (optional)" },
              "subject" => { "type" => "string", "description" => "Subject line" },
              "body" => { "type" => "string", "description" => "HTML body" }
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
      to = require_arg(args, "to")
      recipient = { "email" => to }
      to_name = (args["to_name"] || args[:to_name]).to_s
      recipient["name"] = to_name if to_name.present?

      body = {
        "personalizations" => [ { "to" => [ recipient ] } ],
        "from" => { "email" => require_config("from_email"), "name" => connector.config_value("from_name").to_s },
        "subject" => require_arg(args, "subject"),
        "content" => [ { "type" => "html", "value" => require_arg(args, "body") } ],
        "priorityflag" => 1
      }

      uri = build_uri(base, "/mail/send")
      resp = post_json(uri, body, headers: { "Authorization" => "x-api-key #{require_secret('api_key')}" })
      resp = post_json(uri, body, headers: { "Authorization" => bearer(require_secret("api_key")) }) if resp.code.to_i == 401
      ensure_ok!(resp, "Netcore Email")
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
