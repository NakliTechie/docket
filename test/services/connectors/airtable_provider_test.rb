require "test_helper"

class Connectors::AirtableProviderTest < ActiveSupport::TestCase
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
                         config: { "base_id" => "appABC123", "table_name" => "Leads" }.merge(config))
    conn.credentials_hash = { "access_token" => "pat-secret" }.merge(creds)
    Connectors::AirtableProvider.new(conn)
  end

  # --- create_record ---

  test "create_record posts fields to the base/table path and returns the created record" do
    body = { "id" => "rec123", "fields" => { "Name" => "Ada" }, "createdTime" => "2026-06-13T00:00:00.000Z" }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_record", { "fields" => { "Name" => "Ada", "Stage" => "New" } })
      assert obs["ok"]
      assert_equal "rec123", obs["result"]["id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/v0/appABC123/Leads", req.path
      assert_equal "Bearer pat-secret", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal({ "Name" => "Ada", "Stage" => "New" }, sent["fields"])
    end
  end

  test "create_record CGI-escapes a table_name with spaces in the path" do
    with_http(201, %({"id":"rec1"})) do |reqs|
      prov = provider(config: { "table_name" => "Sales Pipeline" })
      obs = prov.invoke("create_record", { "fields" => { "Name" => "X" } })
      assert obs["ok"]
      assert_equal "/v0/appABC123/Sales+Pipeline", reqs.last.last.path
    end
  end

  test "create_record reads symbol-keyed fields argument" do
    with_http(201, %({"id":"rec2"})) do |reqs|
      obs = provider.invoke("create_record", { fields: { "Name" => "Sym" } })
      assert obs["ok"]
      sent = JSON.parse(reqs.last.last.body)
      assert_equal({ "Name" => "Sym" }, sent["fields"])
    end
  end

  test "create_record requires fields" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_record", {}) }
    end
  end

  test "create_record rejects a blank fields object" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_record", { "fields" => {} }) }
    end
  end

  test "create_record raises on a non-2xx response" do
    with_http(422, %({"error":{"type":"INVALID_REQUEST"}})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_record", { "fields" => { "Name" => "Ada" } }) }
    end
  end

  test "create_record raises when the base_id config is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.config = { "table_name" => "Leads" }
      assert_raises(Connectors::Error) { prov.invoke("create_record", { "fields" => { "Name" => "Ada" } }) }
    end
  end

  test "create_record raises when the table_name config is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.config = { "base_id" => "appABC123" }
      assert_raises(Connectors::Error) { prov.invoke("create_record", { "fields" => { "Name" => "Ada" } }) }
    end
  end

  test "create_record raises when the access_token secret is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_record", { "fields" => { "Name" => "Ada" } }) }
    end
  end

  # --- base_url override ---

  test "a base_url config override still produces the same path" do
    with_http(201, %({"id":"rec1"})) do |reqs|
      prov = provider(config: { "base_url" => "https://airtable.internal.example" })
      obs = prov.invoke("create_record", { "fields" => { "Name" => "Ada" } })
      assert obs["ok"]
      assert_equal "/v0/appABC123/Leads", reqs.last.last.path
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_record is a confirm-class write" do
    assert_equal :confirm, Connectors::AirtableProvider.action("create_record").effective_decision_class
    assert_equal :write, Connectors::AirtableProvider.action("create_record").effect
  end

  test "airtable declares itself as a non-syncing productivity effector" do
    desc = Connectors::AirtableProvider.descriptor
    assert_not desc.syncs?
    assert_equal "Productivity", desc.category
    assert_equal %w[base_id table_name base_url], desc.config_fields
    assert_equal %w[access_token], desc.secret_fields
  end

  test "fetch returns an empty array (effector-only provider)" do
    assert_equal [], provider.fetch
  end
end
