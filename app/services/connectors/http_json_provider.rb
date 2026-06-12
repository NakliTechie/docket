module Connectors
  # Reference provider: GET a JSON array of records from any HTTP(S)
  # endpoint (sync), and POST a JSON body to a configured endpoint (the
  # effector action). Generic enough to prove both halves of the framework
  # end-to-end before the named (Salesforce/HubSpot/…) providers land.
  class HttpJsonProvider < Provider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20

    def self.descriptor
      Descriptor.new(
        key: "http_json", name: "HTTP JSON API", category: "Generic",
        auth: :api_key, config_fields: %w[endpoint_url records_path action_url]
      )
    end

    def self.actions
      [
        Action.new(
          key: "post_json", name: "POST JSON",
          summary: "POST a JSON body to the connector's configured action_url and return the response.",
          params: {
            "type" => "object",
            "properties" => { "body" => { "type" => "object", "description" => "JSON payload to send" } },
            "required" => %w[body]
          },
          effect: :write
        )
      ]
    end

    def fetch
      uri = endpoint_uri("endpoint_url")
      response = request(Net::HTTP::Get.new(uri.request_uri, headers), uri)
      unless response.code.to_i.between?(200, 299)
        raise Connectors::Error, "endpoint returned HTTP #{response.code}"
      end

      records = dig_records(JSON.parse(response.body))
      raise Connectors::Error, "expected a JSON array of records" unless records.is_a?(Array)
      records
    rescue JSON::ParserError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
      raise Connectors::Error, "fetch failed: #{e.class}: #{e.message}"
    end

    def invoke(action_key, args, context = {})
      case action_key.to_s
      when "post_json" then post_json(args, context)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def post_json(args, context)
      uri = endpoint_uri("action_url")
      body = args["body"] || args[:body]
      raise Connectors::Error, "body is required" unless body.is_a?(Hash)

      req = Net::HTTP::Post.new(uri.request_uri, action_headers(context))
      req.body = JSON.generate(body)
      response = request(req, uri)
      unless response.code.to_i.between?(200, 299)
        raise Connectors::Error, "action endpoint returned HTTP #{response.code}"
      end
      { "http_status" => response.code.to_i, "body" => parse_body(response.body) }
    rescue JSON::ParserError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
      raise Connectors::Error, "post_json failed: #{e.class}: #{e.message}"
    end

    def endpoint_uri(config_key)
      url = connector.config_value(config_key).to_s
      raise Connectors::Error, "#{config_key} is required" if url.blank?
      uri = URI.parse(url)
      raise Connectors::Error, "#{config_key} must be http(s)" unless uri.is_a?(URI::HTTP)
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Connectors::Error, "endpoint blocked: #{reason}"
      end
      uri
    rescue URI::InvalidURIError
      raise Connectors::Error, "#{config_key} is not a valid URL"
    end

    def request(req, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(req)
    end

    def headers
      h = { "Accept" => "application/json" }
      token = connector.secret("api_key").to_s
      h["Authorization"] = "Bearer #{token}" if token.present?
      h
    end

    # Outbound action carries the invocation's delegation id so the external
    # system can correlate the side effect back to the agent that caused it.
    def action_headers(context)
      h = headers.merge("Content-Type" => "application/json")
      delegation = context[:invocation]&.delegation_id
      h["X-Docket-Delegation-Id"] = delegation if delegation
      h
    end

    # records_path "data.items" reaches into a wrapped payload; blank = root.
    def dig_records(payload)
      path = connector.config_value("records_path").to_s
      return payload if path.blank?
      path.split(".").reduce(payload) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
    end

    def parse_body(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
