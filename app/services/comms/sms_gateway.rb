module Comms
  # Direct SMS send via the deployment's configured MSG91 connector — the one
  # send path shared by BOTH the agent effector (Connectors::Msg91Provider,
  # which is approval-gated) and automated marketing sequences (system-
  # attributed, no per-send approval). Both reach MSG91's DLT-templated flow
  # API through here, so the SSRF guard and payload shape live in one place.
  #
  # MSG91 sends a registered DLT template (template_id) with variable values,
  # not arbitrary text — so callers pass the template variables, not a body.
  class SmsGateway
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    DEFAULT_BASE = "https://control.msg91.com".freeze
    NET_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError ].freeze

    Error = Class.new(StandardError)

    # The active, fully-configured MSG91 connector this deployment sends through,
    # or nil if none is wired/keyed yet.
    def self.default_connector
      Connector.where(provider: "msg91", status: :active).find(&:configured?)
    end

    def self.available?
      default_connector.present?
    end

    def initialize(connector)
      @connector = connector
    end

    def deliver(mobile:, variables: {})
      mobile = mobile.to_s.strip
      raise Error, "mobile is required" if mobile.blank?
      template = connector.config_value("template_id").to_s
      raise Error, "template_id config is required" if template.blank?

      uri = endpoint("/api/v5/flow/")
      body = {
        template_id: template,
        sender: connector.config_value("sender_id").presence,
        recipients: [ { mobiles: mobile }.merge(variables.is_a?(Hash) ? variables : {}) ]
      }.compact
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json", "authkey" => authkey)
      req.body = JSON.generate(body)
      response = request(req, uri)
      raise Error, "MSG91 returned HTTP #{response.code}" unless response.code.to_i.between?(200, 299)
      { "ok" => true, "mobile" => mobile, "response" => parse(response.body) }
    rescue *NET_ERRORS => e
      raise Error, "sms send failed: #{e.class}: #{e.message}"
    end

    private

    attr_reader :connector

    def authkey
      key = connector.secret("authkey").to_s
      raise Error, "authkey is required" if key.blank?
      key
    end

    def endpoint(path)
      base = connector.config_value("base_url").presence || DEFAULT_BASE
      uri = URI.parse(base.chomp("/") + path)
      raise Error, "base_url must be http(s)" unless uri.is_a?(URI::HTTP)
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Error, "endpoint blocked: #{reason}"
      end
      uri
    rescue URI::InvalidURIError
      raise Error, "base_url is not a valid URL"
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
