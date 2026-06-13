module Connectors
  # Abstract base for AWS providers: holds the static IAM credentials
  # (access_key_id / secret_access_key) + region and signs each request with
  # SigV4 (Connectors::AwsSigv4). Not registered itself — SES, S3, … subclass it
  # and declare their descriptor/actions, calling #signed_request for the wire
  # call. `signed_headers` are both signed and sent (e.g. S3's
  # x-amz-content-sha256); `unsigned_headers` are sent only (e.g. Content-Type).
  class AwsProvider < HttpProvider
    private

    def signer(service)
      AwsSigv4.new(
        access_key: require_secret("access_key_id"),
        secret_key: require_secret("secret_access_key"),
        region: require_config("region"),
        service: service
      )
    end

    def signed_request(method, uri, service:, payload: "", signed_headers: {}, unsigned_headers: {})
      auth = signer(service).sign(method: method, uri: uri, payload: payload, headers: signed_headers)
      request_class = method.to_s.upcase == "PUT" ? Net::HTTP::Put : Net::HTTP::Post
      req = request_class.new(uri.request_uri, base_headers.merge(unsigned_headers).merge(signed_headers).merge(auth))
      req.body = payload
      perform(req, uri)
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
