require "test_helper"

class Connectors::MondayProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t",
                         config: { "board_id" => "12345", "base_url" => "" }.merge(config))
    conn.credentials_hash = { "api_token" => "tok-secret" }.merge(creds)
    Connectors::MondayProvider.new(conn)
  end

  # --- create_item ---

  test "create_item posts a GraphQL mutation with the name as a variable and returns the result" do
    body = { "data" => { "create_item" => { "id" => "987654321" } } }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("create_item", { "name" => "Follow up with Ada" })
      assert obs["ok"]
      assert_equal "987654321", obs["result"]["data"]["create_item"]["id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/v2", req.path
      # monday auth is the RAW token — no "Bearer " prefix.
      assert_equal "tok-secret", req["Authorization"]
      assert_equal "2026-01", req["API-Version"]

      sent = JSON.parse(req.body)
      assert_includes sent["query"], "create_item"
      assert_includes sent["query"], "board_id: $boardId"
      assert_includes sent["query"], "item_name: $itemName"
      assert_equal "12345", sent["variables"]["boardId"]
      assert_equal "Follow up with Ada", sent["variables"]["itemName"]
    end
  end

  test "create_item passes an injection-y name safely as a variable" do
    with_http(200, %({"data":{"create_item":{"id":"1"}}})) do |reqs|
      nasty = "Bad\" ) { delete_board (board_id: 1) } #"
      provider.invoke("create_item", { "name" => nasty })
      sent = JSON.parse(reqs.last.last.body)
      # The raw name lives only in the variables map; the query is untouched.
      assert_equal nasty, sent["variables"]["itemName"]
      assert_not_includes sent["query"], "delete_board"
    end
  end

  test "create_item reads a symbol-keyed name argument" do
    with_http(200, %({"data":{"create_item":{"id":"1"}}})) do |reqs|
      obs = provider.invoke("create_item", { name: "Symbolic" })
      assert obs["ok"]
      assert_equal "Symbolic", JSON.parse(reqs.last.last.body)["variables"]["itemName"]
    end
  end

  test "create_item requires name" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_item", {}) }
    end
  end

  test "create_item raises when name is blank" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_item", { "name" => "   " }) }
    end
  end

  test "create_item raises when the board_id config is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.config = {}
      assert_raises(Connectors::Error) { prov.invoke("create_item", { "name" => "X" }) }
    end
  end

  test "create_item raises when the api_token secret is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_item", { "name" => "X" }) }
    end
  end

  test "create_item raises on a non-2xx response" do
    with_http(401, %({"errors":[{"message":"Not Authenticated"}]})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_item", { "name" => "X" }) }
    end
  end

  # --- base override ---

  test "a base_url config override changes the host but keeps the /v2 path" do
    with_http(200, %({"data":{"create_item":{"id":"1"}}})) do |reqs|
      prov = provider(config: { "base_url" => "https://api.monday.example.com" })
      obs = prov.invoke("create_item", { "name" => "X" })
      assert obs["ok"]
      assert_equal "/v2", reqs.last.last.path
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_item is a confirm-class write" do
    assert_equal :confirm, Connectors::MondayProvider.action("create_item").effective_decision_class
    assert_equal :write, Connectors::MondayProvider.action("create_item").effect
  end

  test "monday declares itself as a non-syncing CRM effector" do
    desc = Connectors::MondayProvider.descriptor
    assert_not desc.syncs?
    assert_equal "monday", desc.key
    assert_equal "CRM & Sales", desc.category
    assert_equal %w[board_id base_url], desc.config_fields
    assert_equal %w[api_token], desc.secret_fields
  end

  test "fetch returns an empty array (effector-only provider)" do
    assert_equal [], provider.fetch
  end
end
