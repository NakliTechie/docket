require "openssl"

module Connectors
  # PayU India — payment verification + refund via the Merchant POST Service.
  # Auth is a SHA-512 checksum over `key|command|var1|salt` (the salt is the
  # secret). Verifying a payment is an autonomous read; issuing a refund is a
  # decision of record (discretionary + adverse). Effector-only.
  class PayuProvider < HttpProvider
    DEFAULT_BASE = "https://info.payu.in".freeze

    def self.descriptor
      Descriptor.new(
        key: "payu", name: "PayU (India)", category: "Payments",
        auth: :none, config_fields: %w[base_url],
        credential_fields: %w[merchant_key merchant_salt], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "verify_payment", name: "Verify payment",
          summary: "Verify a PayU payment by merchant transaction id.",
          params: {
            "type" => "object",
            "properties" => { "txnid" => { "type" => "string", "description" => "Merchant transaction id" } },
            "required" => %w[txnid]
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "refund_payment", name: "Refund payment",
          summary: "Issue a refund against a captured PayU payment.",
          params: {
            "type" => "object",
            "properties" => {
              "mihpayid" => { "type" => "string", "description" => "PayU payment id (mihpayid)" },
              "refund_token" => { "type" => "string", "description" => "A unique token/id for this refund" },
              "amount" => { "type" => "string", "description" => "Refund amount" }
            },
            "required" => %w[mihpayid refund_token amount]
          },
          effect: :irreversible, decision_class: :of_record
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "verify_payment" then verify_payment(args)
      when "refund_payment" then refund_payment(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def verify_payment(args)
      post_command("verify_payment", var1: require_arg(args, "txnid"))
    end

    def refund_payment(args)
      post_command("cancel_refund_transaction",
                   var1: require_arg(args, "mihpayid"),
                   var2: require_arg(args, "refund_token"),
                   var3: require_arg(args, "amount"))
    end

    # PayU info/refund commands: form-POST key+command+vars+hash, where
    # hash = sha512(key|command|var1|salt).
    def post_command(command, var1:, var2: nil, var3: nil)
      key = require_secret("merchant_key")
      salt = require_secret("merchant_salt")
      form = { "key" => key, "command" => command, "var1" => var1, "hash" => checksum(key, command, var1, salt) }
      form["var2"] = var2 if var2
      form["var3"] = var3 if var3

      uri = build_uri(base, "/merchant/postservice.php?form=2")
      resp = ensure_ok!(post_form(uri, form), "PayU")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def checksum(key, command, var1, salt)
      OpenSSL::Digest::SHA512.hexdigest("#{key}|#{command}|#{var1}|#{salt}")
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
