module Connectors
  # Reference provider: GET a JSON array of records from any HTTP(S)
  # endpoint, optionally bearer-authenticated. Generic enough to pull
  # contacts from most REST APIs, and the proof that the framework works
  # end-to-end before the named (Salesforce/HubSpot/…) providers land.
  class HttpJsonProvider < Provider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20

    def self.descriptor
      Descriptor.new(
        key: "http_json", name: "HTTP JSON API", category: "Generic",
        auth: :api_key, config_fields: %w[endpoint_url records_path]
      )
    end

    def fetch
      uri = endpoint_uri
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Connectors::Error, "endpoint blocked: #{reason}"
      end

      response = get(uri)
      unless response.code.to_i.between?(200, 299)
        raise Connectors::Error, "endpoint returned HTTP #{response.code}"
      end

      records = dig_records(JSON.parse(response.body))
      raise Connectors::Error, "expected a JSON array of records" unless records.is_a?(Array)
      records
    rescue JSON::ParserError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
      raise Connectors::Error, "fetch failed: #{e.class}: #{e.message}"
    end

    private

    def endpoint_uri
      url = connector.config_value("endpoint_url").to_s
      raise Connectors::Error, "endpoint_url is required" if url.blank?
      uri = URI.parse(url)
      raise Connectors::Error, "endpoint_url must be http(s)" unless uri.is_a?(URI::HTTP)
      uri
    rescue URI::InvalidURIError
      raise Connectors::Error, "endpoint_url is not a valid URL"
    end

    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(Net::HTTP::Get.new(uri.request_uri, headers))
    end

    def headers
      h = { "Accept" => "application/json" }
      token = connector.credentials_hash["api_key"].to_s
      h["Authorization"] = "Bearer #{token}" if token.present?
      h
    end

    # records_path "data.items" reaches into a wrapped payload; blank = root.
    def dig_records(payload)
      path = connector.config_value("records_path").to_s
      return payload if path.blank?
      path.split(".").reduce(payload) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
    end
  end
end
