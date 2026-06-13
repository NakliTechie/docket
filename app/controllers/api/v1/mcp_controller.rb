module Api
  module V1
    # The Model Context Protocol server face (PG5): a JSON-RPC 2.0 endpoint that
    # exposes the api/v1 surface as MCP tools to agents. Auth + tenant are
    # inherited from BaseController (bearer token, TenantResolution); every
    # tools/call is forwarded back through the real API (Mcp::Dispatch), so no
    # new authority is introduced here.
    class McpController < BaseController
      PROTOCOL_VERSION = "2025-06-18".freeze

      def handle
        message = parse_body
        if message.is_a?(Array)
          responses = message.filter_map { |m| dispatch_message(m) }
          responses.empty? ? head(:accepted) : render(json: responses)
        else
          response = dispatch_message(message)
          response ? render(json: response) : head(:accepted)
        end
      end

      private

      def parse_body
        JSON.parse(request.raw_post)
      rescue JSON::ParserError
        {}
      end

      # → a JSON-RPC response Hash, or nil for a notification (no id).
      def dispatch_message(message)
        return nil unless message.is_a?(Hash)
        id = message["id"]

        result =
          case message["method"]
          when "initialize"      then initialize_result
          when "tools/list"      then { "tools" => Mcp::Catalog.tools }
          when "tools/call"      then tool_call_result(message)
          when "ping"            then {}
          else
            return id.nil? ? nil : error(id, -32601, "method not found: #{message["method"]}")
          end

        id.nil? ? nil : { "jsonrpc" => "2.0", "id" => id, "result" => result }
      rescue Mcp::Error => e
        message["id"].nil? ? nil : error(message["id"], e.code, e.message)
      end

      def initialize_result
        {
          "protocolVersion" => PROTOCOL_VERSION,
          "capabilities" => { "tools" => { "listChanged" => false } },
          "serverInfo" => { "name" => "docket", "version" => "v1" }
        }
      end

      def tool_call_result(message)
        name = message.dig("params", "name")
        operation = Mcp::Catalog.operation(name)
        raise Mcp::Error.new(-32602, "unknown tool: #{name}") unless operation

        outcome = Mcp::Dispatch.call(
          operation, message.dig("params", "arguments") || {},
          authorization: request.authorization, host: request.host, remote_ip: request.remote_ip
        )
        {
          "content" => [ { "type" => "text", "text" => outcome[:text].presence || "{}" } ],
          "isError" => outcome[:status] >= 400
        }
      end

      def error(id, code, message)
        { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }
      end
    end
  end
end
