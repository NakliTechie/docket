module Mcp
  # The MCP tool catalogue, derived from the generated OpenAPI document (PG5) —
  # so the agent-facing tools track the api/v1 surface automatically. Each
  # documented operation becomes one tool: name = method + path, description =
  # the operation summary, inputSchema = its path/query params + request body.
  # Public endpoints (security: []) — the token exchange and the spec itself —
  # are not tools.
  module Catalog
    module_function

    def index
      @index ||= build_index
    end

    # MCP tools/list payload.
    def tools
      index.values.map do |op|
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
