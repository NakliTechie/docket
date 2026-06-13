require "test_helper"

# PG5 — the MCP server face: a JSON-RPC endpoint exposing api/v1 as agent
# tools, with auth, tenant and scopes inherited from the real API.
module Api
  module V1
    class McpTest < ActionDispatch::IntegrationTest
      def rpc(token: @admin, **body)
        headers = { "CONTENT_TYPE" => "application/json" }
        headers.merge!(auth_header(token)) if token
        post "/api/v1/mcp", params: body.to_json, headers: headers
        response.parsed_body
      end

      setup { @admin = api_token_for(users(:admin)) }

      test "the endpoint requires a bearer token" do
        rpc(token: nil, jsonrpc: "2.0", id: 1, method: "tools/list")
        assert_response :unauthorized
      end

      test "initialize returns protocol + server info" do
        res = rpc(jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" })
        assert_response :success
        assert_equal "2.0", res["jsonrpc"]
        assert_equal 1, res["id"]
        assert_equal "docket", res.dig("result", "serverInfo", "name")
        assert res.dig("result", "capabilities", "tools")
      end

      test "tools/list maps api/v1 operations to tools and omits public endpoints" do
        names = rpc(jsonrpc: "2.0", id: 2, method: "tools/list").dig("result", "tools").map { |t| t["name"] }
        assert_includes names, "get_cases"
        assert_includes names, "post_cases"
        assert_includes names, "post_cases_id_transition"
        assert_not(names.any? { |n| n.include?("oauth") || n.include?("openapi") }, "public endpoints aren't tools")
      end

      test "every tool carries a name, description and object inputSchema" do
        tools = rpc(jsonrpc: "2.0", id: 3, method: "tools/list").dig("result", "tools")
        assert tools.all? { |t| t["name"].present? && t["description"].present? }
        assert tools.all? { |t| t.dig("inputSchema", "type") == "object" }
        transition = tools.find { |t| t["name"] == "post_cases_id_transition" }
        assert_includes transition.dig("inputSchema", "required"), "id"
        assert transition.dig("inputSchema", "properties").key?("status")
      end

      test "tools/call reads through the real API (a read returns live data)" do
        Case.create!(subject: "MCP visible case", channel: :staff, contact: contacts(:asha))
        res = rpc(jsonrpc: "2.0", id: 4, method: "tools/call",
                  params: { name: "get_cases", arguments: {} })
        result = res["result"]
        assert_equal false, result["isError"]
        assert_includes result.dig("content", 0, "text"), "MCP visible case"
      end

      test "tools/call performs a write through the real API (path param + body)" do
        kase = Case.create!(subject: "To progress", channel: :staff, contact: contacts(:asha))
        kase.transition_to!(:triaged)
        res = rpc(jsonrpc: "2.0", id: 5, method: "tools/call",
                  params: { name: "post_cases_id_transition", arguments: { "id" => kase.id, "status" => "in_progress" } })
        assert_equal false, res.dig("result", "isError")
        assert kase.reload.status_in_progress?
      end

      test "tools/call inherits service-account scopes (a read-only token can't write)" do
        token = service_token_for(%w[cases:read])
        kase = Case.create!(subject: "Guarded", channel: :staff, contact: contacts(:asha))
        kase.transition_to!(:triaged)
        res = rpc(token: token, jsonrpc: "2.0", id: 6, method: "tools/call",
                  params: { name: "post_cases_id_transition", arguments: { "id" => kase.id, "status" => "in_progress" } })
        assert_equal true, res.dig("result", "isError"), "the inner request is 403 — no cases:write scope"
        assert kase.reload.status_triaged?, "the write did not happen"
      end

      test "an unknown tool is a JSON-RPC invalid-params error" do
        res = rpc(jsonrpc: "2.0", id: 7, method: "tools/call", params: { name: "nope", arguments: {} })
        assert_equal(-32602, res.dig("error", "code"))
      end

      test "an unknown method is method-not-found" do
        res = rpc(jsonrpc: "2.0", id: 8, method: "bogus/method")
        assert_equal(-32601, res.dig("error", "code"))
      end

      test "a malformed JSON body is a JSON-RPC parse error, not a silent 202 (L4)" do
        post "/api/v1/mcp", params: "{ not valid json",
             headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_header(@admin))
        assert_response :success
        assert_equal(-32700, response.parsed_body.dig("error", "code"))
      end

      test "a notification (no id) gets no body" do
        post "/api/v1/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
             headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_header(@admin))
        assert_response :accepted
        assert_predicate response.body.strip, :empty?
      end
    end
  end
end
