module Connectors
  # Effector-only provider: read a Razorpay payment or issue a refund. Basic
  # auth from key_id:key_secret (vaulted). Demonstrates the decision-class
  # range: fetch_payment is :autonomous (read), refund_payment is :of_record
  # (it moves money — a human of record + reasoned order, never auto-approved).
  class RazorpayProvider < Provider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    DEFAULT_BASE = "https://api.razorpay.com".freeze
    NET_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError ].freeze

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

    def fetch
      []
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
      uri = endpoint("/v1/payments/#{payment_id(args)}")
      response = request(Net::HTTP::Get.new(uri.request_uri, auth_headers), uri)
      ok_or_raise(response)
      { "ok" => true, "payment" => parse(response.body) }
    rescue *NET_ERRORS => e
      raise Connectors::Error, "fetch_payment failed: #{e.class}: #{e.message}"
    end

    def refund_payment(args)
      uri = endpoint("/v1/payments/#{payment_id(args)}/refund")
      amount = args["amount"] || args[:amount]
      req = Net::HTTP::Post.new(uri.request_uri, auth_headers.merge("Content-Type" => "application/json"))
      req.body = JSON.generate(amount.present? ? { amount: amount.to_i } : {})
      response = request(req, uri)
      ok_or_raise(response)
      { "ok" => true, "refund" => parse(response.body) }
    rescue *NET_ERRORS => e
      raise Connectors::Error, "refund_payment failed: #{e.class}: #{e.message}"
    end

    def payment_id(args)
      id = (args["payment_id"] || args[:payment_id]).to_s.strip
      raise Connectors::Error, "payment_id is required" if id.blank?
      id
    end

    def auth_headers
      key_id = connector.credentials_hash["key_id"].to_s
      secret = connector.credentials_hash["key_secret"].to_s
      raise Connectors::Error, "key_id and key_secret are required" if key_id.blank? || secret.blank?
      token = [ "#{key_id}:#{secret}" ].pack("m0")
      { "Authorization" => "Basic #{token}", "Accept" => "application/json" }
    end

    def endpoint(path)
      base = connector.config_value("base_url").presence || DEFAULT_BASE
      uri = URI.parse(base.chomp("/") + path)
      raise Connectors::Error, "base_url must be http(s)" unless uri.is_a?(URI::HTTP)
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Connectors::Error, "endpoint blocked: #{reason}"
      end
      uri
    rescue URI::InvalidURIError
      raise Connectors::Error, "base_url is not a valid URL"
    end

    def request(req, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(req)
    end

    def ok_or_raise(response)
      return if response.code.to_i.between?(200, 299)
      raise Connectors::Error, "Razorpay returned HTTP #{response.code}"
    end

    def parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
