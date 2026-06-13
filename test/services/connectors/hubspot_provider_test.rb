require "test_helper"

class Connectors::HubspotProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: {}.merge(config))
    conn.credentials_hash = { "access_token" => "pat-na1-secret" }.merge(creds)
    Connectors::HubspotProvider.new(conn)
  end

  # --- create_contact ---

  test "create_contact posts properties and returns the created contact" do
    body = { "id" => "501", "properties" => { "email" => "a@b.com", "firstname" => "Ada" } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_contact",
                            { "email" => "a@b.com", "firstname" => "Ada", "company" => "Acme" })
      assert obs["ok"]
      assert_equal "501", obs["contact"]["id"]

      req = reqs.last.last
      assert_equal "/crm/v3/objects/contacts", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Bearer pat-na1-secret", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "a@b.com", sent["properties"]["email"]
      assert_equal "Ada", sent["properties"]["firstname"]
      assert_equal "Acme", sent["properties"]["company"]
      # Optional keys that were not supplied are omitted.
      assert_not sent["properties"].key?("lastname")
      assert_not sent["properties"].key?("phone")
    end
  end

  test "create_contact requires email" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "firstname" => "Ada" }) }
    end
  end

  test "create_contact raises on a non-2xx response" do
    with_http(401, %({"status":"error"})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "email" => "a@b.com" }) }
    end
  end

  # --- create_deal ---

  test "create_deal posts the deal properties and returns the created deal" do
    body = { "id" => "9001", "properties" => { "dealname" => "Q3 renewal", "amount" => "5000" } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_deal", { "dealname" => "Q3 renewal", "amount" => "5000" })
      assert obs["ok"]
      assert_equal "9001", obs["deal"]["id"]

      req = reqs.last.last
      assert_equal "/crm/v3/objects/deals", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Bearer pat-na1-secret", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "Q3 renewal", sent["properties"]["dealname"]
      assert_equal "5000", sent["properties"]["amount"]
    end
  end

  test "create_deal omits amount when not provided" do
    with_http(201, %({"id":"9002","properties":{"dealname":"Lead"}})) do |reqs|
      provider.invoke("create_deal", { "dealname" => "Lead" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "Lead", sent["properties"]["dealname"]
      assert_not sent["properties"].key?("amount")
    end
  end

  test "create_deal requires dealname" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_deal", { "amount" => "100" }) }
    end
  end

  test "create_deal raises on a non-2xx response" do
    with_http(500) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_deal", { "dealname" => "X" }) }
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- fetch (syncs) ---

  test "fetch returns the flattened properties of each contact" do
    body = {
      "results" => [
        { "id" => "1", "properties" => { "email" => "a@b.com", "firstname" => "Ada" } },
        { "id" => "2", "properties" => { "email" => "c@d.com", "lastname" => "Byron" } }
      ]
    }.to_json
    with_http(200, body) do |reqs|
      records = provider.fetch
      assert_equal 2, records.length
      assert_equal "a@b.com", records.first["email"]
      assert_equal "Byron", records.last["lastname"]

      req = reqs.last.last
      assert_equal "/crm/v3/objects/contacts?properties=email,firstname,lastname,phone", req.path
      assert_kind_of Net::HTTP::Get, req
      assert_equal "Bearer pat-na1-secret", req["Authorization"]
    end
  end

  test "fetch returns an empty array when there are no results" do
    with_http(200, %({"results":[]})) do |_reqs|
      assert_equal [], provider.fetch
    end
  end

  test "fetch raises on a non-2xx response" do
    with_http(403) do |_reqs|
      assert_raises(Connectors::Error) { provider.fetch }
    end
  end

  # --- config + decision class ---

  test "a configured base_url is accepted and the action still succeeds" do
    with_http(201, %({"id":"1","properties":{"email":"a@b.com"}})) do |reqs|
      prov = provider(config: { "base_url" => "https://api.eu1.hubapi.com" })
      obs = prov.invoke("create_contact", { "email" => "a@b.com" })
      assert obs["ok"]
      # The path is unchanged; only the (stubbed) host differs from the default.
      assert_equal "/crm/v3/objects/contacts", reqs.last.last.path
    end
  end

  test "create_contact raises when the access_token secret is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_contact", { "email" => "a@b.com" }) }
    end
  end

  test "create_contact and create_deal are confirm-class writes" do
    assert_equal :confirm, Connectors::HubspotProvider.action("create_contact").effective_decision_class
    assert_equal :confirm, Connectors::HubspotProvider.action("create_deal").effective_decision_class
  end

  test "hubspot declares itself as a syncing CRM provider" do
    assert Connectors::HubspotProvider.descriptor.syncs?
    assert_equal "CRM & Sales", Connectors::HubspotProvider.descriptor.category
    assert_equal %w[access_token], Connectors::HubspotProvider.descriptor.secret_fields
  end
end
