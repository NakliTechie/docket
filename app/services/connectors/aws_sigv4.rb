require "openssl"

module Connectors
  # AWS Signature Version 4 signer — the shared auth seam for the AWS providers
  # (SES, S3, …). Given a request (method, URI, payload, extra signed headers)
  # it returns the headers to add: Authorization + X-Amz-Date. `host` and
  # `x-amz-date` are always signed; the caller adds service-specific signed
  # headers (e.g. S3's `x-amz-content-sha256`) via `headers:` and must also send
  # them on the wire. Verified against AWS's published "get-vanilla" SigV4 test
  # vector (see test).
  #
  #   signer = AwsSigv4.new(access_key:, secret_key:, region: "ap-south-1", service: "ses")
  #   signed = signer.sign(method: "POST", uri: uri, payload: body)
  #   # → { "Authorization" => "AWS4-HMAC-SHA256 Credential=…", "X-Amz-Date" => "…Z" }
  class AwsSigv4
    ALGORITHM = "AWS4-HMAC-SHA256".freeze

    def initialize(access_key:, secret_key:, region:, service:)
      @access_key = access_key
      @secret_key = secret_key
      @region = region
      @service = service
    end

    # SHA-256 hex of a payload — exposed so callers can set a matching
    # `x-amz-content-sha256` header (S3 requires it).
    def self.hashed_payload(payload)
      OpenSSL::Digest::SHA256.hexdigest(payload.to_s)
    end

    def sign(method:, uri:, payload: "", headers: {}, now: Time.now.utc)
      now = now.utc
      amz_date = now.strftime("%Y%m%dT%H%M%SZ")
      date = now.strftime("%Y%m%d")
      payload_hash = self.class.hashed_payload(payload)

      signed = { "host" => uri.host }
      headers.each { |k, v| signed[k.to_s.downcase] = v.to_s }
      signed["x-amz-date"] = amz_date

      ordered = signed.keys.sort
      signed_headers = ordered.join(";")
      canonical_headers = ordered.map { |k| "#{k}:#{signed[k].strip}\n" }.join

      canonical_request = [
        method.to_s.upcase,
        canonical_path(uri),
        canonical_query(uri),
        canonical_headers,
        signed_headers,
        payload_hash
      ].join("\n")

      scope = "#{date}/#{@region}/#{@service}/aws4_request"
      string_to_sign = [ ALGORITHM, amz_date, scope, hex(sha256(canonical_request)) ].join("\n")
      signature = hex(hmac(signing_key(date), string_to_sign))

      {
        "Authorization" => "#{ALGORITHM} Credential=#{@access_key}/#{scope}, " \
                           "SignedHeaders=#{signed_headers}, Signature=#{signature}",
        "X-Amz-Date" => amz_date
      }
    end

    private

    def signing_key(date)
      k_date = hmac("AWS4#{@secret_key}", date)
      k_region = hmac(k_date, @region)
      k_service = hmac(k_region, @service)
      hmac(k_service, "aws4_request")
    end

    def canonical_path(uri)
      uri.path.to_s.empty? ? "/" : uri.path
    end

    # Canonical query string: params sorted by key, value-encoded. Empty for our
    # body-carrying requests, but correct if a query is present.
    def canonical_query(uri)
      return "" if uri.query.to_s.empty?
      URI.decode_www_form(uri.query)
         .map { |k, v| [ aws_escape(k), aws_escape(v) ] }
         .sort
         .map { |k, v| "#{k}=#{v}" }
         .join("&")
    end

    def aws_escape(value)
      CGI.escape(value.to_s).gsub("+", "%20").gsub("%7E", "~")
    end

    def hmac(key, data) = OpenSSL::HMAC.digest("SHA256", key, data)
    def sha256(data) = OpenSSL::Digest::SHA256.digest(data)
    def hex(bytes) = bytes.unpack1("H*")
  end
end
