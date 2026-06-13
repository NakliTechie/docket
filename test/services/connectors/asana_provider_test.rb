require "test_helper"

class Connectors::AsanaProviderTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @r)
  end
  def with_http(code, body = "{}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def provider(config: {}, creds: {})
    conn = Connector.new(provider: "http_json", name: "t", config: { "project_id" => "12345" }.merge(config))
    conn.credentials_hash = { "access_token" => "asana-pat" }.merge(creds)
    Connectors::AsanaProvider.new(conn)
  end

  # --- create_task ---

  test "create_task posts a wrapped task payload and returns the created record" do
    body = { "data" => { "gid" => "9001", "name" => "Ship it", "resource_type" => "task" } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_task", { "name" => "Ship it", "notes" => "do the thing" })
      assert obs["ok"]
      assert_equal "9001", obs["result"]["data"]["gid"]

      req = reqs.last.last
      assert_equal "/api/1.0/tasks", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Bearer asana-pat", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "Ship it", sent["data"]["name"]
      assert_equal "do the thing", sent["data"]["notes"]
      assert_equal [ "12345" ], sent["data"]["projects"]
    end
  end

  test "create_task omits notes when not supplied" do
    with_http(201, %({"data":{"gid":"1","name":"x"}})) do |reqs|
      provider.invoke("create_task", { "name" => "x" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "x", sent["data"]["name"]
      assert_not sent["data"].key?("notes")
    end
  end

  test "create_task omits the projects array when no project_id is configured" do
    with_http(201, %({"data":{"gid":"1","name":"x"}})) do |reqs|
      prov = provider(config: { "project_id" => "" })
      prov.invoke("create_task", { "name" => "x" })
      sent = JSON.parse(reqs.last.last.body)
      assert_not sent["data"].key?("projects")
    end
  end

  test "create_task accepts symbol-keyed args" do
    with_http(201, %({"data":{"gid":"1","name":"x"}})) do |reqs|
      provider.invoke("create_task", { name: "x", notes: "n" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "x", sent["data"]["name"]
      assert_equal "n", sent["data"]["notes"]
    end
  end

  test "create_task requires name" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_task", { "notes" => "orphan" }) }
    end
  end

  test "create_task treats a blank name as missing" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_task", { "name" => "  " }) }
    end
  end

  test "create_task raises on a non-2xx response" do
    with_http(401, %({"errors":[{"message":"Not Authorized"}]})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_task", { "name" => "x" }) }
    end
  end

  test "create_task raises when the access_token secret is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_task", { "name" => "x" }) }
    end
  end

  # --- config ---

  test "a configured base_url overrides the default host" do
    with_http(201, %({"data":{"gid":"1","name":"x"}})) do |reqs|
      prov = provider(config: { "base_url" => "https://asana.example.com/api/1.0" })
      obs = prov.invoke("create_task", { "name" => "x" })
      assert obs["ok"]
      assert_equal "/api/1.0/tasks", reqs.last.last.path
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_task is a confirm-class write" do
    assert_equal :write, Connectors::AsanaProvider.action("create_task").effect
    assert_equal :confirm, Connectors::AsanaProvider.action("create_task").effective_decision_class
  end

  test "asana declares itself as an effector-only productivity provider" do
    desc = Connectors::AsanaProvider.descriptor
    assert_equal "asana", desc.key
    assert_equal "Productivity", desc.category
    assert_not desc.syncs?
    assert_equal %w[access_token], desc.secret_fields
    assert_equal %w[project_id base_url], desc.config_fields
  end

  test "fetch returns no records for this effector-only provider" do
    assert_equal [], provider.fetch
  end
end
