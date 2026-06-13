module Connectors
  # Effector-only provider: look up a Stripe PaymentIntent or issue a refund.
  # Auth is the secret key as a Bearer token (vaulted). Stripe request bodies
  # are FORM-encoded (application/x-www-form-urlencoded), not JSON — writes go
  # through post_form. Demonstrates the decision-class range: fetch_payment_intent
  # is :autonomous (read-only), create_refund is :of_record (it moves money — a
  # human of record + reasoned order, never auto-approved).
  class StripeProvider < HttpProvider
    DEFAULT_BASE = "https://api.stripe.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "stripe", name: "Stripe (payments)", category: "Payments",
        auth: :none, config_fields: %w[base_url], credential_fields: %w[secret_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "fetch_payment_intent", name: "Fetch payment intent",
          summary: "Look up a Stripe PaymentIntent by id (read-only).",
          params: {
            "type" => "object",
            "properties" => { "payment_intent_id" => { "type" => "string", "description" => "PaymentIntent id (pi_…)" } },
            "required" => %w[payment_intent_id]
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "create_refund", name: "Create refund",
          summary: "Refund a Stripe payment. Moves money — a decision of record.",
          params: {
            "type" => "object",
            "properties" => {
              "payment_intent_id" => { "type" => "string", "description" => "PaymentIntent id to refund (pi_…)" },
              "amount" => { "type" => "integer", "description" => "Amount in minor units (cents); omit for a full refund" }
            },
            "required" => %w[payment_intent_id]
          },
          effect: :irreversible, decision_class: :of_record
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "fetch_payment_intent" then fetch_payment_intent(args)
      when "create_refund"        then create_refund(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def fetch_payment_intent(args)
      uri = build_uri(base, "/v1/payment_intents/#{payment_intent_id(args)}")
      response = get(uri, headers: auth_headers)
      ensure_ok!(response, "Stripe")
      { "ok" => true, "payment_intent" => parse_json(response.body) }
    end

    def create_refund(args)
      form = { "payment_intent" => payment_intent_id(args) }
      amount = args["amount"] || args[:amount]
      form["amount"] = amount.to_i if amount.present?

      uri = build_uri(base, "/v1/refunds")
      response = post_form(uri, form, headers: auth_headers)
      ensure_ok!(response, "Stripe")
      { "ok" => true, "refund" => parse_json(response.body) }
    end

    def payment_intent_id(args)
      id = (args["payment_intent_id"] || args[:payment_intent_id]).to_s.strip
      raise Connectors::Error, "payment_intent_id is required" if id.blank?
      id
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("secret_key")) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
