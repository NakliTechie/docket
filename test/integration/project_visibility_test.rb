require "test_helper"

class ProjectVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:pep)
    @project.update!(visibility: :restricted, member_ids: [])
    @item = work_items(:pep_one)
    @worker = users(:agent_a)
  end

  test "a non-member cannot discover a restricted project or its work in HTML" do
    sign_in_as @worker

    get projects_path
    assert_response :success
    refute_includes response.body, @project.name

    get project_board_path(@project)
    assert_response :not_found
    get work_item_path(@item)
    assert_response :not_found
  end

  test "membership reveals a restricted project without granting new role permissions" do
    ActsAsTenant.with_tenant(tenants(:primary)) { @project.update!(member_ids: [ @worker.id ]) }
    sign_in_as @worker

    get project_board_path(@project)
    assert_response :success
    get work_item_path(@item)
    assert_response :success
    refute ProjectPolicy.new(@worker, Project.new).create?, "membership is visibility, not project administration"
  end

  test "project administrators retain access to every restricted project" do
    sign_in_as users(:admin)
    get project_board_path(@project)
    assert_response :success
  end

  test "human and service-account APIs enforce restricted project visibility" do
    human_token = api_token_for(@worker)
    service_token = service_token_for(%w[work:read])

    get "/api/v1/projects", headers: auth_header(human_token)
    refute_includes response.parsed_body["data"].pluck("id"), @project.id
    get "/api/v1/work_items/#{@item.id}", headers: auth_header(human_token)
    assert_response :not_found

    get "/api/v1/projects", headers: auth_header(service_token)
    refute_includes response.parsed_body["data"].pluck("id"), @project.id,
                    "a read integration has no human membership and sees tenant-wide projects only"

    ActsAsTenant.with_tenant(tenants(:primary)) { @project.update!(member_ids: [ @worker.id ]) }
    get "/api/v1/work_items/#{@item.id}", headers: auth_header(human_token)
    assert_response :success
  end

  def mcp_project_text(token)
    post "/api/v1/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: "get_projects", arguments: {} } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }.merge(auth_header(token))
    response.parsed_body.dig("result", "content", 0, "text")
  end

  test "MCP hides a restricted project from a non-member" do
    token = api_token_for(@worker)
    refute_includes mcp_project_text(token), @project.name
  end

  test "MCP reveals a restricted project to a member" do
    @project.update!(member_ids: [ @worker.id ])
    token = api_token_for(@worker)
    assert_includes mcp_project_text(token), @project.name
  end
end
