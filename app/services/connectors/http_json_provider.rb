module Connectors
  # Reference provider: GET a JSON array of records from any HTTP(S)
  # endpoint (sync), and POST a JSON body to a configured endpoint (the
  # effector action). Generic enough to prove both halves of the framework
  # end-to-end before the named (Salesforce/HubSpot/…) providers land.
  class HttpJsonProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "http_json", name: "HTTP JSON API", category: "Generic",
        auth: :api_key, config_fields: %w[endpoint_url records_path action_url],
        required_credential_fields: [] # bearer token is optional
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
      response = get(build_uri(require_config("endpoint_url")), headers: token_headers)
      ensure_ok!(response, "endpoint")
      records = dig_records(parse_json(response.body))
      raise Connectors::Error, "expected a JSON array of records" unless records.is_a?(Array)
      records
    end

    def invoke(action_key, args, context = {})
      case action_key.to_s
      when "post_json" then perform_post_json(args, context)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    # The "post_json" action (distinct from HttpProvider#post_json, the wire helper).
    def perform_post_json(args, context)
      body = args["body"] || args[:body]
      raise Connectors::Error, "body is required" unless body.is_a?(Hash)

      response = post_json(build_uri(require_config("action_url")), body, headers: action_headers(context))
      ensure_ok!(response, "action endpoint")
      { "http_status" => response.code.to_i, "body" => parse_json(response.body) }
    end

    def token_headers
      token = connector.secret("api_key").to_s
      token.present? ? { "Authorization" => bearer(token) } : {}
    end

    # Outbound action carries the invocation's delegation id so the external
    # system can correlate the side effect back to the agent that caused it.
    def action_headers(context)
      delegation = context[:invocation]&.delegation_id
      delegation ? token_headers.merge("X-Docket-Delegation-Id" => delegation) : token_headers
    end

    # records_path "data.items" reaches into a wrapped payload; blank = root.
    def dig_records(payload)
      path = connector.config_value("records_path").to_s
      return payload if path.blank?
      path.split(".").reduce(payload) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
    end
  end
end
