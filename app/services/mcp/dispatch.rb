module Mcp
  # Bridges an MCP tools/call to the real api/v1 endpoint (PG5). It rebuilds the
  # HTTP request the operation describes — substituting path params, threading
  # query params, JSON-encoding the rest as the body — forwards the caller's
  # bearer + host, and re-enters the Rails stack. So auth, tenant resolution,
  # Pundit and service-account scopes are enforced exactly as for any API call;
  # the MCP face adds no new authority of its own.
  module Dispatch
    BASE = "/api/v1".freeze

    module_function

    def call(operation, arguments, authorization:, host:, remote_ip: nil)
      args = (arguments || {}).dup
      path = operation[:path_template].dup
      operation[:path_names].each { |name| path = path.sub("{#{name}}", args.delete(name).to_s) }

      query = {}
      operation[:query_names].each { |q| query[q] = args.delete(q) if args.key?(q) }

      write = !%w[GET DELETE].include?(operation[:http_method])
      body = write ? JSON.generate(args) : ""

      full_path = +"#{BASE}#{path}"
      qs = query.compact.to_query
      full_path << "?#{qs}" if qs.present?

      env = Rack::MockRequest.env_for(
        full_path,
        method: operation[:http_method],
        input: body,
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json",
        "HTTP_AUTHORIZATION" => authorization.to_s,
        "HTTP_HOST" => host.to_s
      )
      env["REMOTE_ADDR"] = remote_ip if remote_ip

      status, _headers, rack_body = Rails.application.call(env)
      text = +""
      rack_body.each { |part| text << part }
      rack_body.close if rack_body.respond_to?(:close)

      { status: status.to_i, text: text }
    end
  end
end
