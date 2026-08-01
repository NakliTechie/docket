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

      # H11: credential/identity plumbing is never exposed as an agent tool, and
      # naming one anyway is rejected as unknown.
      test "tools deny credential and identity resources" do
        names = rpc(jsonrpc: "2.0", id: 20, method: "tools/list").dig("result", "tools").map { |t| t["name"] }
        denied = %w[api_tokens service_accounts settings webhook_endpoints users]
        names.each do |n|
          resource = n.split("_", 2).last # drop the http verb
          assert_not denied.any? { |d| resource.start_with?(d) }, "#{n} exposes a denied resource"
        end

        res = rpc(jsonrpc: "2.0", id: 21, method: "tools/call",
                  params: { name: "post_api_tokens", arguments: {} })
        assert_match(/unknown tool/, res.dig("error", "message"))
      end

      test "nested credential and identity resources are structurally denied" do
        assert Mcp::Catalog.denied_resource?("/connectors/{connector_id}/settings")
        assert Mcp::Catalog.denied_resource?("/projects/{project_id}/users/{id}")
        refute Mcp::Catalog.denied_resource?("/projects/{project_id}/work_items/{id}")
      end

      # H10: tools/call is gated on the tenant's entitlement, not just tools/list.
      test "tools/call rejects a tool whose module the tenant lacks" do
        tenants(:primary).set_feature!("crm", false)
        res = rpc(jsonrpc: "2.0", id: 22, method: "tools/call",
                  params: { name: "get_leads", arguments: {} })
        assert_match(/unknown tool/, res.dig("error", "message"))
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

      test "two tools/call messages in one request preserve outer tenant and actor context" do
        kase = Case.create!(subject: "Batch progress", channel: :staff, contact: contacts(:asha))
        kase.transition_to!(:triaged)
        payload = [
          { jsonrpc: "2.0", id: 31, method: "tools/call",
            params: { name: "post_cases_id_transition",
                      arguments: { id: kase.id, status: "in_progress" } } },
          { jsonrpc: "2.0", id: 32, method: "tools/call",
            params: { name: "post_cases_id_transition",
                      arguments: { id: kase.id, status: "waiting_on_customer" } } }
        ]

        post "/api/v1/mcp", params: payload.to_json,
             headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_header(@admin))

        assert_response :success
        assert_equal [ false, false ], response.parsed_body.map { |item| item.dig("result", "isError") }
        assert kase.reload.status_waiting_on_customer?
        status_audits = AuditEntry.where(auditable: kase).order(:id).select { |entry|
          entry.changeset.to_h.key?("status")
        }
        assert_equal users(:admin).id, status_audits.last.actor_id
        assert_equal tenants(:primary).id, status_audits.last.tenant_id
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
