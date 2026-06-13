module Connectors
  # E-commerce effector + sync: act on a Shopify store's orders and pull its
  # customers inbound. Auth is a custom-app access token sent in the
  # `X-Shopify-Access-Token` header (NOT a Bearer token). The base is derived
  # from config: https://{shop_domain}/admin/api/{api_version} where
  # shop_domain looks like "acme.myshopify.com" and api_version defaults to
  # "2025-01" when blank.
  #
  # Decision-class range: create_fulfillment is :confirm (an operational
  # write a human signs off), create_refund is :of_record (it moves money —
  # a human of record + reasoned order, never auto-approved).
  class ShopifyProvider < HttpProvider
    DEFAULT_API_VERSION = "2025-01".freeze

    def self.descriptor
      Descriptor.new(
        key: "shopify", name: "Shopify", category: "E-commerce",
        auth: :none, config_fields: %w[shop_domain api_version],
        credential_fields: %w[access_token], syncs: true
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_fulfillment", name: "Create fulfilment",
          summary: "Mark an order fulfilled (optionally with tracking).",
          params: {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "Shopify order id" },
              "tracking_number" => { "type" => "string", "description" => "Carrier tracking number" },
              "notify_customer" => { "type" => "boolean", "description" => "Email the customer on fulfilment" }
            },
            "required" => %w[order_id]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "create_refund", name: "Create refund",
          summary: "Refund an order. Moves money — a decision of record.",
          params: {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "Shopify order id to refund" },
              "note" => { "type" => "string", "description" => "Reason / note recorded on the refund" }
            },
            "required" => %w[order_id]
          },
          effect: :irreversible, decision_class: :of_record
        )
      ]
    end

    # Pull customers inbound; they map to Contact via the connector
    # field-mapping. GET /customers.json → { "customers" => [...] }.
    def fetch
      uri = build_uri(api_base, "/customers.json")
      response = ensure_ok!(get(uri, headers: auth_headers), "Shopify")
      body = parse_json(response.body)
      records = body.is_a?(Hash) ? body["customers"] : body
      records.is_a?(Array) ? records : []
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_fulfillment" then create_fulfillment(args)
      when "create_refund"      then create_refund(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    # NOTE: modern Shopify prefers the GraphQL fulfillmentCreateV2 mutation
    # (which needs a fulfillment_order_id); the REST create-fulfillment
    # endpoint still works for custom apps and is fine for v1 here.
    def create_fulfillment(args)
      order_id = require_arg(args, "order_id")
      fulfillment = {}
      tracking = (args["tracking_number"] || args[:tracking_number]).to_s
      fulfillment["tracking_number"] = tracking if tracking.present?
      notify = args["notify_customer"] || args[:notify_customer]
      fulfillment["notify_customer"] = !!notify unless notify.nil?

      uri = build_uri(api_base, "/fulfillments.json")
      response = ensure_ok!(post_json(uri, { "fulfillment" => fulfillment.merge("order_id" => order_id) }, headers: auth_headers), "Shopify")
      { "ok" => true, "fulfillment" => parse_json(response.body) }
    end

    def create_refund(args)
      order_id = require_arg(args, "order_id")
      refund = {}
      note = (args["note"] || args[:note]).to_s
      refund["note"] = note if note.present?

      uri = build_uri(api_base, "/orders/#{order_id}/refunds.json")
      response = ensure_ok!(post_json(uri, { "refund" => refund }, headers: auth_headers), "Shopify")
      { "ok" => true, "refund" => parse_json(response.body) }
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end

    # https://{shop_domain}/admin/api/{api_version}
    def api_base
      domain = require_config("shop_domain")
      version = connector.config_value("api_version").presence || DEFAULT_API_VERSION
      "https://#{domain}/admin/api/#{version}"
    end

    def auth_headers
      { "X-Shopify-Access-Token" => require_secret("access_token") }
    end
  end
end
