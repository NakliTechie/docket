module Connectors
  # Effector-only provider: look up a Cashfree PG order or issue a refund
  # against one. Cashfree authenticates with three headers — x-client-id and
  # x-client-secret (both vaulted) plus an x-api-version (config, dated string,
  # default "2023-08-01"). Demonstrates the decision-class range: fetch_order
  # is :autonomous (read-only), create_refund is :of_record (it moves money — a
  # human of record + reasoned order, never auto-approved).
  class CashfreeProvider < HttpProvider
    DEFAULT_BASE = "https://api.cashfree.com".freeze
    DEFAULT_API_VERSION = "2023-08-01".freeze

    def self.descriptor
      Descriptor.new(
        key: "cashfree", name: "Cashfree (payments)", category: "Payments",
        auth: :none, config_fields: %w[base_url api_version],
        credential_fields: %w[client_id client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "fetch_order", name: "Fetch order",
          summary: "Look up a Cashfree order by id (read-only).",
          params: {
            "type" => "object",
            "properties" => { "order_id" => { "type" => "string", "description" => "Cashfree order id" } },
            "required" => %w[order_id]
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "create_refund", name: "Create refund",
          summary: "Refund a Cashfree order. Moves money — a decision of record.",
          params: {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "Order id to refund" },
              "refund_amount" => { "type" => "number", "description" => "Amount to refund (in the order's currency)" },
              "refund_id" => { "type" => "string", "description" => "Caller-supplied idempotent refund id" },
              "refund_note" => { "type" => "string", "description" => "Optional note attached to the refund" }
            },
            "required" => %w[order_id refund_amount refund_id]
          },
          effect: :irreversible, decision_class: :of_record
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "fetch_order"   then fetch_order(args)
      when "create_refund" then create_refund(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def fetch_order(args)
      uri = build_uri(base, "/pg/orders/#{require_arg(args, 'order_id')}")
      response = get(uri, headers: auth_headers)
      ensure_ok!(response, "Cashfree")
      { "ok" => true, "order" => parse_json(response.body) }
    end

    def create_refund(args)
      order_id = require_arg(args, "order_id")
      body = {
        "refund_amount" => require_amount(args),
        "refund_id" => require_arg(args, "refund_id")
      }
      note = args["refund_note"] || args[:refund_note]
      body["refund_note"] = note if note.present?

      uri = build_uri(base, "/pg/orders/#{order_id}/refunds")
      response = post_json(uri, body, headers: auth_headers)
      ensure_ok!(response, "Cashfree")
      { "ok" => true, "refund" => parse_json(response.body) }
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end

    def require_amount(args)
      raw = args["refund_amount"] || args[:refund_amount]
      raise Connectors::Error, "refund_amount is required" if raw.nil? || raw.to_s.strip.empty?
      raw
    end

    def auth_headers
      {
        "x-client-id" => require_secret("client_id"),
        "x-client-secret" => require_secret("client_secret"),
        "x-api-version" => connector.config_value("api_version").presence || DEFAULT_API_VERSION
      }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end
  end
end
