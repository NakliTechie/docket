require "tempfile"

module Imports
  # Minimal read-only HTTP client for migration sources. It validates and pins
  # DNS through Docket's outbound guard, never follows redirects implicitly,
  # and never forwards source credentials to a different attachment origin.
  class HttpSource
    class Error < StandardError; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30
    MAX_JSON_BYTES = 20.megabytes

    attr_accessor :watermark
    attr_reader :base_uri

    def initialize(base_url:, headers: {}, allow_insecure: false)
      @base_uri = URI.parse(base_url.to_s)
      raise Error, "migration source must be http(s)" unless @base_uri.is_a?(URI::HTTP)
      if @base_uri.scheme != "https" && !allow_insecure
        raise Error, "migration source must use HTTPS"
      end
      raise Error, "migration source URL may not contain credentials" if @base_uri.userinfo
      if (reason = Docket::OutboundUrl.blocked_reason(@base_uri.host))
        raise Error, "migration source blocked: #{reason}"
      end

      @headers = { "Accept" => "application/json" }.merge(headers)
    rescue URI::InvalidURIError
      raise Error, "migration source URL is invalid"
    end

    def download_attachment(row)
      raw_url = row["attachment_url"].presence || row["content_url"].presence ||
                row["url"].presence || row["content"].presence
      raise Error, "attachment URL is missing" if raw_url.blank?

      uri = absolute_uri(raw_url)
      response = request(uri, headers: credential_headers_for(uri), stream: true) do |body|
        tempfile = Tempfile.new([ "docket-import", File.extname(filename_for(row)) ])
        tempfile.binmode
        size = 0
        body.each do |chunk|
          size += chunk.bytesize
          if size > AttachableValidation::MAX_FILE_SIZE
            tempfile.close!
            raise Error, "attachment exceeds #{AttachableValidation::MAX_FILE_SIZE} bytes"
          end
          tempfile.write(chunk)
        end
        tempfile.rewind
        tempfile
      end
      {
        io: response.fetch(:value), filename: filename_for(row),
        content_type: row["content_type"].presence || row["mimeType"].presence ||
                      response.fetch(:response)["Content-Type"]&.split(";")&.first
      }
    end

    private

    def get_json(path, query: nil)
      uri = absolute_uri(path)
      uri.query = URI.encode_www_form(query.compact) if query
      response = request(uri, headers: credential_headers_for(uri))
      body = response.fetch(:value)
      raise Error, "JSON response exceeded #{MAX_JSON_BYTES} bytes" if body.bytesize > MAX_JSON_BYTES

      [ JSON.parse(body), response.fetch(:response) ]
    rescue JSON::ParserError => e
      raise Error, "migration source returned invalid JSON: #{e.message}"
    end

    def request(uri, headers:, stream: false, redirects: 3, &block)
      validate_uri!(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.ipaddr = Docket::OutboundUrl.vetted_address(uri.host, port: uri.port)
      request = Net::HTTP::Get.new(uri.request_uri, headers)
      response = nil
      value = nil
      http.request(request) do |received|
        response = received
        code = received.code.to_i
        if code.between?(300, 399) && received["Location"].present?
          raise Error, "too many migration source redirects" if redirects.zero?

          target = URI.join(uri.to_s, received["Location"])
          return request(target, headers: credential_headers_for(target), stream: stream,
                         redirects: redirects - 1, &block)
        end
        raise Error, "migration source returned HTTP #{received.code}" unless code.between?(200, 299)

        value = if stream
          block.call(received.enum_for(:read_body))
        else
          received.body.to_s
        end
      end
      { response: response, value: value }
    rescue Docket::OutboundUrl::Blocked, Docket::OutboundUrl::ResolutionError,
           SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
      raise Error, "migration source request failed: #{e.class}: #{e.message}"
    end

    def validate_uri!(uri)
      raise Error, "migration source must be http(s)" unless uri.is_a?(URI::HTTP)
      if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
        raise Error, "migration source blocked: #{reason}"
      end
    end

    def absolute_uri(value)
      URI.join(base_uri.to_s.end_with?("/") ? base_uri.to_s : "#{base_uri}/", value.to_s)
    rescue URI::InvalidURIError
      raise Error, "migration source URL is invalid"
    end

    def credential_headers_for(uri)
      same_origin?(uri) ? @headers : { "Accept" => @headers.fetch("Accept", "*/*") }
    end

    def same_origin?(uri)
      uri.scheme == base_uri.scheme && uri.host == base_uri.host && uri.port == base_uri.port
    end

    def filename_for(row)
      row["name"].presence || row["filename"].presence || row["file_name"].presence ||
        "attachment-#{row['id']}"
    end
  end
end
