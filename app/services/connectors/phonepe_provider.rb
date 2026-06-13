require "openssl"

module Connectors
  # PhonePe PG — check a payment's status. Auth is the `X-VERIFY` header:
  # sha256(requestPath + saltKey) + "###" + saltIndex. merchant_id + salt_index
  # are config; salt_key is the secret. Status check is an autonomous read.
  # Effector-only.
  class PhonepeProvider < HttpProvider
    DEFAULT_BASE = "https://api.phonepe.com/apis/hermes".freeze

    def self.descriptor
      Descriptor.new(
        key: "phonepe", name: "PhonePe", category: "Payments",
        auth: :none, config_fields: %w[merchant_id salt_index base_url],
        credential_fields: %w[salt_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "check_status", name: "Check payment status",
          summary: "Check the status of a PhonePe payment by merchant transaction id.",
          params: {
            "type" => "object",
            "properties" => {
              "transaction_id" => { "type" => "string", "description" => "Merchant transaction id" }
            },
            "required" => %w[transaction_id]
          },
          effect: :read, decision_class: :autonomous
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "check_status" then check_status(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def check_status(args)
      txn_id = require_arg(args, "transaction_id")
      merchant_id = require_config("merchant_id")
      path = "/pg/v1/status/#{merchant_id}/#{txn_id}"

      uri = build_uri(base, path)
      headers = { "X-VERIFY" => x_verify(path), "X-MERCHANT-ID" => merchant_id, "Content-Type" => "application/json" }
      resp = ensure_ok!(get(uri, headers: headers), "PhonePe")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    # sha256(path + saltKey) "###" saltIndex
    def x_verify(path)
      digest = OpenSSL::Digest::SHA256.hexdigest("#{path}#{require_secret('salt_key')}")
      [ digest, salt_index ].join("###")
    end

    def salt_index
      connector.config_value("salt_index").to_s.strip.presence || "1"
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
