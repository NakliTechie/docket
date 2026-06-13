module Connectors
  # Amazon S3 — put an object into a bucket, SigV4-signed (service "s3"). Static
  # IAM credentials + region + bucket. S3 requires the payload hash as a signed
  # `x-amz-content-sha256` header. Writing is :confirm. Effector-only.
  class AmazonS3Provider < AwsProvider
    def self.descriptor
      Descriptor.new(
        key: "amazon_s3", name: "Amazon S3", category: "Storage & Files",
        auth: :none, config_fields: %w[region bucket],
        credential_fields: %w[access_key_id secret_access_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "put_object", name: "Put object",
          summary: "Upload an object to the configured S3 bucket.",
          params: {
            "type" => "object",
            "properties" => {
              "key" => { "type" => "string", "description" => "Object key (path within the bucket)" },
              "content" => { "type" => "string", "description" => "Object body" },
              "content_type" => { "type" => "string", "description" => "MIME type (default text/plain)" }
            },
            "required" => %w[key content]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "put_object" then put_object(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def put_object(args)
      key = require_arg(args, "key").delete_prefix("/")
      content = require_arg(args, "content")
      content_type = (args["content_type"] || args[:content_type]).to_s.strip.presence || "text/plain"

      host = "#{require_config('bucket')}.s3.#{require_config('region')}.amazonaws.com"
      # RFC3986-encode each key segment (preserving "/") so a key with a space
      # or special char produces a path that matches the SigV4 canonical path —
      # otherwise SignatureDoesNotMatch (L6).
      encoded_key = key.split("/", -1).map { |seg| ERB::Util.url_encode(seg) }.join("/")
      uri = build_uri("https://#{host}", "/#{encoded_key}")
      resp = signed_request("PUT", uri, service: "s3", payload: content,
                            signed_headers: { "x-amz-content-sha256" => AwsSigv4.hashed_payload(content) },
                            unsigned_headers: { "Content-Type" => content_type })
      ensure_ok!(resp, "Amazon S3")
      { "ok" => true, "key" => key, "etag" => resp["etag"] }
    end
  end
end
