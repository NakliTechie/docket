module Connectors
  # Effector-only provider: read a Razorpay payment or issue a refund. Basic
  # auth from key_id:key_secret (vaulted). Demonstrates the decision-class
  # range: fetch_payment is :autonomous (read), refund_payment is :of_record
  # (it moves money — a human of record + reasoned order, never auto-approved).
  class RazorpayProvider < HttpProvider
    DEFAULT_BASE = "https://api.razorpay.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "razorpay", name: "Razorpay (payments)", category: "Payments",
        auth: :none, config_fields: %w[base_url], credential_fields: %w[key_id key_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "fetch_payment", name: "Fetch payment",
          summary: "Look up a Razorpay payment by id (read-only).",
          params: { "type" => "object", "properties" => { "payment_id" => { "type" => "string" } },
                    "required" => %w[payment_id] },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "refund_payment", name: "Refund payment",
          summary: "Issue a refund against a Razorpay payment. Moves money — a decision of record.",
          params: {
            "type" => "object",
            "properties" => {
              "payment_id" => { "type" => "string" },
              "amount" => { "type" => "integer", "description" => "Amount in paise; omit for a full refund" }
            },
            "required" => %w[payment_id]
          },
          effect: :irreversible, decision_class: :of_record
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "fetch_payment"  then fetch_payment(args)
      when "refund_payment" then refund_payment(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def fetch_payment(args)
      response = get(endpoint("/v1/payments/#{payment_id(args)}"), headers: auth_headers)
      ensure_ok!(response, "Razorpay")
      { "ok" => true, "payment" => parse_json(response.body) }
    end

    def refund_payment(args)
      amount = args["amount"] || args[:amount]
      body = amount.present? ? { amount: amount.to_i } : {}
      response = post_json(endpoint("/v1/payments/#{payment_id(args)}/refund"), body, headers: auth_headers)
      ensure_ok!(response, "Razorpay")
      { "ok" => true, "refund" => parse_json(response.body) }
    end

    def payment_id(args)
      id = (args["payment_id"] || args[:payment_id]).to_s.strip
      raise Connectors::Error, "payment_id is required" if id.blank?
      id
    end

    def auth_headers
      { "Authorization" => basic_auth(require_secret("key_id"), require_secret("key_secret")) }
    end

    def endpoint(path)
      build_uri(connector.config_value("base_url").presence || DEFAULT_BASE, path)
    end
  end
end
