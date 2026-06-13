require "test_helper"

class Connectors::ClickupProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: { "list_id" => "9001" }.merge(config))
    conn.credentials_hash = { "api_token" => "pk_secret_token" }.merge(creds)
    Connectors::ClickupProvider.new(conn)
  end

  # --- create_task ---

  test "create_task posts name with optional description and returns the created task" do
    body = { "id" => "abc123", "name" => "Ship the docs", "url" => "https://app.clickup.com/t/abc123" }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("create_task",
                            { "name" => "Ship the docs", "description" => "Write the release notes" })
      assert obs["ok"]
      assert_equal "abc123", obs["result"]["id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/api/v2/list/9001/task", req.path
      # ClickUp auth is the RAW token — no "Bearer " prefix.
      assert_equal "pk_secret_token", req["Authorization"]

      sent = JSON.parse(req.body)
      assert_equal "Ship the docs", sent["name"]
      assert_equal "Write the release notes", sent["description"]
    end
  end

  test "create_task omits description when not provided" do
    with_http(200, %({"id":"t1"})) do |reqs|
      provider.invoke("create_task", { "name" => "Standalone" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "Standalone", sent["name"]
      assert_not sent.key?("description")
    end
  end

  test "create_task reads symbol-keyed args" do
    with_http(200, %({"id":"t2"})) do |reqs|
      provider.invoke("create_task", { name: "Sym task", description: "Sym body" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "Sym task", sent["name"]
      assert_equal "Sym body", sent["description"]
    end
  end

  test "create_task requires name" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_task", { "description" => "no title" }) }
    end
  end

  test "create_task raises on a blank name" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_task", { "name" => "   " }) }
    end
  end

  test "create_task raises on a non-2xx response" do
    with_http(401, %({"err":"Token invalid"})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_task", { "name" => "X" }) }
    end
  end

  # --- base override + required config/secret ---

  test "create_task honours a base_url config override" do
    with_http(200, %({"id":"t3"})) do |reqs|
      prov = provider(config: { "base_url" => "https://clickup.example.test/api/v2" })
      obs = prov.invoke("create_task", { "name" => "Override" })
      assert obs["ok"]
      # Path is unchanged; only the (stubbed) host differs.
      assert_equal "/api/v2/list/9001/task", reqs.last.last.path
    end
  end

  test "create_task raises when the list_id config is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.config = {}
      assert_raises(Connectors::Error) { prov.invoke("create_task", { "name" => "X" }) }
    end
  end

  test "create_task raises when the api_token secret is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_task", { "name" => "X" }) }
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_task is a confirm-class write" do
    assert_equal :confirm, Connectors::ClickupProvider.action("create_task").effective_decision_class
    assert_equal :write, Connectors::ClickupProvider.action("create_task").effect
  end

  test "clickup declares itself as a non-syncing productivity effector" do
    desc = Connectors::ClickupProvider.descriptor
    assert_not desc.syncs?
    assert_equal "Productivity", desc.category
    assert_equal %w[list_id base_url], desc.config_fields
    assert_equal %w[api_token], desc.secret_fields
  end

  test "fetch returns an empty array (effector-only provider)" do
    assert_equal [], provider.fetch
  end
end
