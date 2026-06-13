require "test_helper"

class Connectors::PipedriveProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: { "company_domain" => "acme" }.merge(config))
    conn.credentials_hash = { "api_token" => "tok-secret" }.merge(creds)
    Connectors::PipedriveProvider.new(conn)
  end

  # --- create_person ---

  test "create_person posts name with array-wrapped email/phone and returns the created person" do
    body = { "success" => true, "data" => { "id" => 42, "name" => "Ada Lovelace" } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_person",
                            { "name" => "Ada Lovelace", "email" => "ada@x.com", "phone" => "+15551234" })
      assert obs["ok"]
      assert_equal 42, obs["person"]["data"]["id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      # Auth is a query param, not a header.
      assert_equal "/v1/persons?api_token=tok-secret", req.path
      assert_nil req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "Ada Lovelace", sent["name"]
      assert_equal [ "ada@x.com" ], sent["email"]
      assert_equal [ "+15551234" ], sent["phone"]
    end
  end

  test "create_person omits email and phone when not provided" do
    with_http(201, %({"data":{"id":1}})) do |reqs|
      provider.invoke("create_person", { "name" => "Solo" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "Solo", sent["name"]
      assert_not sent.key?("email")
      assert_not sent.key?("phone")
    end
  end

  test "create_person requires name" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_person", { "email" => "a@b.com" }) }
    end
  end

  test "create_person raises on a non-2xx response" do
    with_http(401, %({"success":false})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_person", { "name" => "Ada" }) }
    end
  end

  # --- create_deal ---

  test "create_deal posts title with optional value and currency" do
    body = { "data" => { "id" => 9001, "title" => "Q3 renewal" } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_deal",
                            { "title" => "Q3 renewal", "value" => "5000", "currency" => "USD" })
      assert obs["ok"]
      assert_equal 9001, obs["deal"]["data"]["id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/v1/deals?api_token=tok-secret", req.path
      sent = JSON.parse(req.body)
      assert_equal "Q3 renewal", sent["title"]
      assert_equal "5000", sent["value"]
      assert_equal "USD", sent["currency"]
    end
  end

  test "create_deal omits value and currency when not provided" do
    with_http(201, %({"data":{"id":1,"title":"Lead"}})) do |reqs|
      provider.invoke("create_deal", { "title" => "Lead" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "Lead", sent["title"]
      assert_not sent.key?("value")
      assert_not sent.key?("currency")
    end
  end

  test "create_deal requires title" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_deal", { "value" => "100" }) }
    end
  end

  test "create_deal raises on a non-2xx response" do
    with_http(500) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_deal", { "title" => "X" }) }
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- config + credentials ---

  test "a different company_domain config still succeeds with the same path" do
    with_http(201, %({"data":{"id":1}})) do |reqs|
      prov = provider(config: { "company_domain" => "globex" })
      obs = prov.invoke("create_person", { "name" => "Ada" })
      assert obs["ok"]
      # The path (and query) are unchanged; only the (stubbed) host differs.
      assert_equal "/v1/persons?api_token=tok-secret", reqs.last.last.path
    end
  end

  test "create_person raises when the company_domain config is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.config = {}
      assert_raises(Connectors::Error) { prov.invoke("create_person", { "name" => "Ada" }) }
    end
  end

  test "create_person raises when the api_token secret is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_person", { "name" => "Ada" }) }
    end
  end

  # --- descriptor + decision class ---

  test "create_person and create_deal are confirm-class writes" do
    assert_equal :confirm, Connectors::PipedriveProvider.action("create_person").effective_decision_class
    assert_equal :confirm, Connectors::PipedriveProvider.action("create_deal").effective_decision_class
    assert_equal :write, Connectors::PipedriveProvider.action("create_person").effect
  end

  test "pipedrive declares itself as a non-syncing CRM effector" do
    desc = Connectors::PipedriveProvider.descriptor
    assert_not desc.syncs?
    assert_equal "CRM & Sales", desc.category
    assert_equal %w[company_domain], desc.config_fields
    assert_equal %w[api_token], desc.secret_fields
  end

  test "fetch returns an empty array (effector-only provider)" do
    assert_equal [], provider.fetch
  end
end
