require "test_helper"

# The effector exception lane: a human-of-record approves or rejects the
# write/irreversible actions an agent proposed through a connector.
class ConnectorInvocationsTest < ActionDispatch::IntegrationTest
  def connector(auto_approve: [])
    Connector.create!(name: "Effector", provider: "http_json", target: "contacts",
      config: { "action_url" => "https://api.example.com/do" },
      field_mapping: { "external_id" => "id" },
      enabled_actions: %w[post_json], auto_approve_actions: auto_approve)
  end

  def agent
    ServiceAccount.create!(name: "Triage agent", scopes: %w[connectors:invoke])
  end

  def propose(on_behalf_of: "case:1")
    Connectors::Invoke.call(connector, "post_json",
      args: { "body" => { "x" => 1 } }, principal: agent,
      on_behalf_of: on_behalf_of, reasoning: "citizen requested it")
  end

  # --- network stub ---
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    def initialize(response) = @response = response
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(_req) = @response
  end
  def with_http(response)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(response) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "admin reviews the pending queue and an action's detail" do
    inv = propose
    sign_in_as users(:admin)

    get admin_connector_invocations_path
    assert_response :success
    assert_match "post_json", response.body
    assert_match "case:1", response.body

    get admin_connector_invocation_path(inv)
    assert_response :success
    assert_match "citizen requested it", response.body
  end

  test "admin approves a proposed action and it executes as the human-of-record" do
    inv = propose
    sign_in_as users(:admin)
    with_http(FakeResponse.new("200", '{"ok":true}')) do
      post approve_admin_connector_invocation_path(inv)
    end
    assert_redirected_to admin_connector_invocation_path(inv)
    assert inv.reload.status_succeeded?
    assert_equal users(:admin), inv.approved_by
  end

  test "admin rejects a proposed action and it never runs" do
    inv = propose
    sign_in_as users(:admin)
    post reject_admin_connector_invocation_path(inv)
    assert inv.reload.status_rejected?
    assert_nil inv.result
  end

  test "a supervisor is a valid human-of-record for the queue" do
    propose
    sign_in_as users(:supervisor)
    get admin_connector_invocations_path
    assert_response :success
  end

  test "a readonly user cannot review the effector queue" do
    propose
    sign_in_as users(:readonly)
    get admin_connector_invocations_path
    assert_response :forbidden
  end

  test "the default queue shows only actions awaiting approval" do
    auto = with_http(FakeResponse.new("200", '{"ok":true}')) do
      Connectors::Invoke.call(connector(auto_approve: %w[post_json]), "post_json",
        args: { "body" => { "x" => 1 } }, principal: agent, on_behalf_of: "case:auto")
    end
    assert auto.status_succeeded?
    sign_in_as users(:admin)

    get admin_connector_invocations_path
    assert_response :success
    assert_no_match "case:auto", response.body

    get admin_connector_invocations_path(filter: "all")
    assert_match "case:auto", response.body
  end
end
