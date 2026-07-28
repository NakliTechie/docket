module Mcp
  # The MCP tool catalogue, derived from the generated OpenAPI document (PG5) —
  # so the agent-facing tools track the api/v1 surface automatically. Each
  # documented operation becomes one tool: name = method + path, description =
  # the operation summary, inputSchema = its path/query params + request body.
  # Public endpoints (security: []) — the token exchange and the spec itself —
  # are not tools.
  module Catalog
    # H11: resources an agent must NEVER reach through MCP — minting/revoking API
    # tokens, creating service accounts, editing deploy settings (which hold the
    # LLM/SMTP secrets), configuring outbound webhooks, and managing user
    # identities. These are platform plumbing that api_path_enabled? does not gate
    # (no feature owns them), so without this deny-list every agent was handed
    # tools for them. Denied at the index level, so tools/list hides them AND
    # tools/call rejects them as an unknown tool.
    DENIED_RESOURCES = %w[api_tokens service_accounts settings webhook_endpoints users].freeze

    module_function

    def denied_resource?(path)
      DENIED_RESOURCES.include?(path.to_s.delete_prefix("/").split("/").first.to_s)
    end

    def index
      @index ||= build_index
    end

    # MCP tools/list payload, filtered to what the tenant in scope actually has.
    # Filtering happens HERE, not in build_index: the index is static and
    # memoized across requests, while entitlements are per tenant.
    def tools
      index.values
           .select { |op| Features.api_path_enabled?(op[:path_template]) }
           .map do |op|
             { "name" => op[:name], "description" => op[:description], "inputSchema" => op[:input_schema] }
           end
    end

    def operation(name)
      index[name.to_s]
    end

    # Test/reload hook: drop the memo (the catalogue is derived from static
    # enums, so this only matters across code reloads).
    def reset! = @index = nil

    def build_index
      doc = Docket::Openapi.document.deep_stringify_keys
      result = {}
      doc.fetch("paths", {}).each do |path, methods|
        next if path == "/mcp" # the MCP endpoint itself is not a tool
        next if denied_resource?(path) # H11: credential/identity plumbing is never a tool

        methods.each do |http_method, op|
          next unless op.is_a?(Hash) && op["summary"].present?
          next if op["security"] == [] # public, non-tool endpoint

          name = tool_name(http_method, path)
          result[name] = {
            name: name,
            http_method: http_method.upcase,
            path_template: path,
            description: op["summary"],
            path_names: path.scan(/\{(\w+)\}/).flatten,
            query_names: Array(op["parameters"]).select { |p| p["in"] == "query" }.map { |p| p["name"] },
            input_schema: input_schema(op)
          }
        end
      end
      result
    end

    def input_schema(op)
      props = {}
      required = []
      Array(op["parameters"]).each do |p|
        props[p["name"]] = p["schema"] || { "type" => "string" }
        required << p["name"] if p["required"]
      end
      body = op.dig("requestBody", "content", "application/json", "schema", "properties")
      props.merge!(body) if body.is_a?(Hash)

      schema = { "type" => "object", "properties" => props }
      schema["required"] = required if required.any?
      schema
    end

    # post /cases/{id}/transition → "post_cases_id_transition"
    def tool_name(method, path)
      slug = path.gsub(/[{}]/, "").gsub(%r{/+}, "_").sub(/\A_/, "").gsub(/_+/, "_")
      "#{method}_#{slug}"
    end
  end
end
