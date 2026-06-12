module Connectors
  # Effector-only provider: send a templated SMS to a citizen via MSG91 (the
  # dominant India CPaaS). Auth is the `authkey` header (vaulted). Citizen-
  # facing comms default to :confirm — a human reviews before it goes out
  # (the connector can auto-approve it if the operator trusts the template).
  class Msg91Provider < Provider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    DEFAULT_BASE = "https://control.msg91.com".freeze
    NET_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError ].freeze

    def self.descriptor
      Descriptor.new(
        key: "msg91", name: "MSG91 (SMS / WhatsApp)", category: "Communications",
        auth: :none, config_fields: %w[sender_id template_id base_url],
        credential_fields: %w[authkey], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_sms", name: "Send SMS",
          summary: "Send a DLT-templated SMS to a citizen's mobile number via MSG91.",
          params: {
            "type" => "object",
            "properties" => {
              "mobile" => { "type" => "string", "description" => "Recipient mobile (E.164 or 10-digit)" },
              "variables" => { "type" => "object", "description" => "Template variable values" }
            },
            "required" => %w[mobile]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def fetch
      []
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_sms" then send_sms(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_sms(args)
      mobile = (args["mobile"] || args[:mobile]).to_s.strip
      raise Connectors::Error, "mobile is required" if mobile.blank?
      template = connector.config_value("template_id").to_s
      raise Connectors::Error, "template_id config is required" if template.blank?

      uri = endpoint("/api/v5/flow/")
      body = {
        template_id: template,
        sender: connector.config_value("sender_id").presence,
        recipients: [ { mobiles: mobile }.merge(variables(args)) ]
      }.compact
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json", "authkey" => authkey)
      req.body = JSON.generate(body)
      response = request(req, uri)
      raise Connectors::Error, "MSG91 returned HTTP #{response.code}" unless response.code.to_i.between?(200, 299)
      { "ok" => true, "mobile" => mobile, "response" => parse(response.body) }
    rescue *NET_ERRORS => e
      raise Connectors::Error, "send_sms failed: #{e.class}: #{e.message}"
    end

    def variables(args)
      vars = args["variables"] || args[:variables]
      vars.is_a?(Hash) ? vars : {}
    end

    def authkey
      key = connector.secret("authkey").to_s
      raise Connectors::Error, "authkey is required" if key.blank?
      key
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

    def parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
