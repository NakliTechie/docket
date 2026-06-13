require "test_helper"

class Connectors::NotionProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: { "database_id" => "db-123" }.merge(config))
    conn.credentials_hash = { "api_token" => "notion-secret" }.merge(creds)
    Connectors::NotionProvider.new(conn)
  end

  # --- create_page ---

  test "create_page posts a database page and returns the created record" do
    body = { "object" => "page", "id" => "page-1", "parent" => { "database_id" => "db-123" } }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("create_page", { "title" => "Ship the thing" })
      assert obs["ok"]
      assert_equal "page-1", obs["result"]["id"]

      req = reqs.last.last
      assert_equal "/v1/pages", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Bearer notion-secret", req["Authorization"]
      assert_equal "2022-06-28", req["Notion-Version"]
      sent = JSON.parse(req.body)
      assert_equal "db-123", sent["parent"]["database_id"]
      assert_equal "Ship the thing", sent["properties"]["Name"]["title"][0]["text"]["content"]
    end
  end

  test "create_page accepts symbol-keyed args" do
    with_http(200, %({"id":"page-1"})) do |reqs|
      provider.invoke("create_page", { title: "Symbol title" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "Symbol title", sent["properties"]["Name"]["title"][0]["text"]["content"]
    end
  end

  test "create_page requires title" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_page", {}) }
    end
  end

  test "create_page treats a blank title as missing" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_page", { "title" => "  " }) }
    end
  end

  test "create_page requires the database_id config" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.config = {}
      assert_raises(Connectors::Error) { prov.invoke("create_page", { "title" => "x" }) }
    end
  end

  test "create_page raises when the api_token secret is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_page", { "title" => "x" }) }
    end
  end

  test "create_page raises on a non-2xx response" do
    with_http(401, %({"object":"error","status":401})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_page", { "title" => "x" }) }
    end
  end

  # --- config ---

  test "a configured base_url is accepted and the action still succeeds" do
    with_http(200, %({"id":"page-1"})) do |reqs|
      prov = provider(config: { "base_url" => "https://api.notion.com" })
      obs = prov.invoke("create_page", { "title" => "x" })
      assert obs["ok"]
      assert_equal "/v1/pages", reqs.last.last.path
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_page is a confirm-class write" do
    assert_equal :write, Connectors::NotionProvider.action("create_page").effect
    assert_equal :confirm, Connectors::NotionProvider.action("create_page").effective_decision_class
  end

  test "notion declares itself as an effector-only productivity provider" do
    desc = Connectors::NotionProvider.descriptor
    assert_equal "notion", desc.key
    assert_equal "Productivity", desc.category
    assert_not desc.syncs?
    assert_equal %w[api_token], desc.secret_fields
    assert_equal %w[database_id base_url], desc.config_fields
  end

  test "fetch returns no records for this effector-only provider" do
    assert_equal [], provider.fetch
  end
end
