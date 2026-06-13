module Connectors
  # Shared plumbing for HTTP(S) providers — the base most named providers
  # (comms, payments, CRM, support, e-commerce…) extend. It owns the SSRF-
  # guarded URI build, the Net::HTTP call with timeouts + error wrapping,
  # JSON/form bodies, response parsing, and auth-header + required-field
  # helpers. A subclass declares .descriptor / .actions, implements #invoke
  # (and #fetch if it syncs), and uses these for the wire calls:
  #
  #   uri  = build_uri(require_config("base_url"), "/v1/messages")
  #   resp = post_json(uri, { text: "hi" }, headers: { "Authorization" => bearer(require_secret("token")) })
  #   ensure_ok!(resp, "Provider")
  #   { "ok" => true, "result" => parse_json(resp.body) }
  class HttpProvider < Provider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    NET_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError ].freeze

    def fetch
      [] # effector-only by default; sync providers override.
    end

    private

    # Build an SSRF-guarded http(s) URI from a base + optional path/query.
    # Raises Connectors::Error on a blank base, non-http scheme, blocked host,
    # or malformed URL.
    def build_uri(base, path = "")
      raise Connectors::Error, "endpoint base is required" if base.to_s.strip.empty?
      uri = URI.parse(base.to_s.chomp("/") + path.to_s)
      raise Connectors::Error, "endpoint must be http(s)" unless uri.is_a?(URI::HTTP)
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Connectors::Error, "endpoint blocked: #{reason}"
      end
      uri
    rescue URI::InvalidURIError
      raise Connectors::Error, "endpoint is not a valid URL"
    end

    def get(uri, headers: {})
      perform(Net::HTTP::Get.new(uri.request_uri, base_headers.merge(headers)), uri)
    end

    def post_json(uri, body, headers: {})
      req = Net::HTTP::Post.new(uri.request_uri, base_headers.merge("Content-Type" => "application/json").merge(headers))
      req.body = JSON.generate(body)
      perform(req, uri)
    end

    def post_form(uri, form, headers: {})
      req = Net::HTTP::Post.new(uri.request_uri,
                                base_headers.merge("Content-Type" => "application/x-www-form-urlencoded").merge(headers))
      req.body = URI.encode_www_form(form)
      perform(req, uri)
    end

    def put_json(uri, body, headers: {})
      req = Net::HTTP::Put.new(uri.request_uri, base_headers.merge("Content-Type" => "application/json").merge(headers))
      req.body = JSON.generate(body)
      perform(req, uri)
    end

    def patch_json(uri, body, headers: {})
      req = Net::HTTP::Patch.new(uri.request_uri, base_headers.merge("Content-Type" => "application/json").merge(headers))
      req.body = JSON.generate(body)
      perform(req, uri)
    end

    def perform(req, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(req)
    rescue *NET_ERRORS => e
      raise Connectors::Error, "request failed: #{e.class}: #{e.message}"
    end

    def ensure_ok!(response, label = "endpoint")
      code = response.code.to_i
      return response if code.between?(200, 299)
      raise Connectors::Error, "#{label} returned HTTP #{response.code}"
    end

    def parse_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end

    def base_headers
      { "Accept" => "application/json" }
    end

    def basic_auth(user, password = "")
      "Basic " + [ "#{user}:#{password}" ].pack("m0")
    end

    def bearer(token)
      "Bearer #{token}"
    end

    # Read a required secret (vault, then shared credential) or raise.
    def require_secret(field)
      value = connector.secret(field).to_s
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end

    # Read a required non-secret config value or raise.
    def require_config(field)
      value = connector.config_value(field).to_s
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
