module Connectors
  # E-commerce effector + sync for a WooCommerce store (WordPress + the
  # WooCommerce REST API v3). Auth is HTTP Basic over https with the store's
  # consumer_key:consumer_secret API credential pair. The base is the store
  # URL itself (e.g. https://shop.example.com); endpoints hang off
  # /wp-json/wc/v3 under it.
  #
  # Both writes are :confirm — operational order edits an AI prepares and a
  # human signs off before they take effect.
  class WoocommerceProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "woocommerce", name: "WooCommerce", category: "E-commerce",
        auth: :none, config_fields: %w[store_url],
        credential_fields: %w[consumer_key consumer_secret], syncs: true
      )
    end

    def self.actions
      [
        Action.new(
          key: "update_order_status", name: "Update order status",
          summary: "Update a WooCommerce order's status (e.g. processing, completed).",
          params: {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "WooCommerce order id" },
              "status" => { "type" => "string", "description" => "New order status, e.g. processing, completed, cancelled" }
            },
            "required" => %w[order_id status]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "create_order_note", name: "Create order note",
          summary: "Add a note to a WooCommerce order.",
          params: {
            "type" => "object",
            "properties" => {
              "order_id" => { "type" => "string", "description" => "WooCommerce order id to note" },
              "note" => { "type" => "string", "description" => "Note body" },
              "customer_note" => { "type" => "boolean", "description" => "Whether the note is visible to the customer" }
            },
            "required" => %w[order_id note]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "update_order_status" then update_order_status(args)
      when "create_order_note"   then create_order_note(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    # Pull customers inbound; they map to Contact via the connector
    # field-mapping. GET /wp-json/wc/v3/customers → a JSON array.
    def fetch
      uri = build_uri(base, "/wp-json/wc/v3/customers")
      response = ensure_ok!(get(uri, headers: auth_headers), "WooCommerce")
      records = parse_json(response.body)
      records.is_a?(Array) ? records : []
    end

    private

    def update_order_status(args)
      order_id = require_arg(args, "order_id")
      status = require_arg(args, "status")

      uri = build_uri(base, "/wp-json/wc/v3/orders/#{order_id}")
      response = ensure_ok!(put_json(uri, { "status" => status }, headers: auth_headers), "WooCommerce")
      { "ok" => true, "order" => parse_json(response.body) }
    end

    def create_order_note(args)
      order_id = require_arg(args, "order_id")
      note = require_arg(args, "note")
      body = { "note" => note }
      customer_note = args.key?("customer_note") ? args["customer_note"] : args[:customer_note]
      body["customer_note"] = !!customer_note unless customer_note.nil?

      uri = build_uri(base, "/wp-json/wc/v3/orders/#{order_id}/notes")
      response = ensure_ok!(post_json(uri, body, headers: auth_headers), "WooCommerce")
      { "ok" => true, "note" => parse_json(response.body) }
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end

    def base
      require_config("store_url")
    end

    def auth_headers
      { "Authorization" => basic_auth(require_secret("consumer_key"), require_secret("consumer_secret")) }
    end
  end
end
