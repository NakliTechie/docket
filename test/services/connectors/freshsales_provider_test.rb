require "test_helper"

# Effector-only Freshsales (Freshworks CRM) provider: create a contact or a
# deal. Auth is the Freshworks token header (Authorization: Token token=<api_key>);
# base derived from the bundle subdomain
# (https://{bundle_domain}.myfreshworks.com/crm/sales).
class Connectors::FreshsalesProviderTest < ActiveSupport::TestCase
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
                         config: { "bundle_domain" => "acme" }.merge(config))
    conn.credentials_hash = { "api_key" => "key_123" }.merge(creds)
    Connectors::FreshsalesProvider.new(conn)
  end

  EXPECTED_AUTH = "Token token=key_123".freeze

  # --- descriptor / registration shape ---

  test "declares an effector-only CRM descriptor with bundle_domain config and api_key secret" do
    d = Connectors::FreshsalesProvider.descriptor
    assert_equal "freshsales", d.key
    assert_equal "Freshsales (CRM)", d.name
    assert_equal "CRM & Sales", d.category
    assert_not d.syncs?
    assert_equal %w[bundle_domain], d.config_fields
    assert_equal %w[api_key], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision classes (CRM writes a salesperson works need a human) ---

  test "create_contact is a confirm-class write" do
    action = Connectors::FreshsalesProvider.action("create_contact")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
  end

  test "create_deal is a confirm-class write" do
    action = Connectors::FreshsalesProvider.action("create_deal")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
  end

  # --- create_contact ---

  test "create_contact POSTs to /api/contacts with the token header and nested contact body" do
    with_http(201, '{"contact":{"id":42,"first_name":"Ada"}}') do |reqs|
      obs = provider.invoke("create_contact",
                            { "first_name" => "Ada", "last_name" => "Lovelace",
                              "email" => "ada@acme.com", "mobile_number" => "+15551234" })
      assert obs["ok"]
      assert_equal 42, obs["contact"]["contact"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/crm/sales/api/contacts", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]
      assert_equal "application/json", req["Content-Type"]

      contact = JSON.parse(req.body)["contact"]
      assert_equal "Ada", contact["first_name"]
      assert_equal "Lovelace", contact["last_name"]
      assert_equal "ada@acme.com", contact["email"]
      assert_equal "+15551234", contact["mobile_number"]
    end
  end

  test "create_contact omits optional fields that were not supplied" do
    with_http(201, '{"contact":{"id":7}}') do |reqs|
      provider.invoke("create_contact", { "first_name" => "Solo" })
      contact = JSON.parse(reqs.last.last.body)["contact"]
      assert_equal "Solo", contact["first_name"]
      assert_not contact.key?("last_name")
      assert_not contact.key?("email")
      assert_not contact.key?("mobile_number")
    end
  end

  test "create_contact requires a first_name" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "email" => "x@acme.com" }) }
    end
  end

  test "create_contact raises on a non-2xx response" do
    with_http(422, '{"errors":[]}') do
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "first_name" => "Ada" }) }
    end
  end

  # --- create_deal ---

  test "create_deal POSTs to /api/deals with the nested deal body" do
    with_http(201, '{"deal":{"id":9001,"name":"Q3 renewal"}}') do |reqs|
      obs = provider.invoke("create_deal", { "name" => "Q3 renewal", "amount" => "5000" })
      assert obs["ok"]
      assert_equal 9001, obs["deal"]["deal"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/crm/sales/api/deals", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]

      deal = JSON.parse(req.body)["deal"]
      assert_equal "Q3 renewal", deal["name"]
      assert_equal "5000", deal["amount"]
    end
  end

  test "create_deal omits amount when not provided" do
    with_http(201, '{"deal":{"id":9002,"name":"Lead"}}') do |reqs|
      provider.invoke("create_deal", { "name" => "Lead" })
      deal = JSON.parse(reqs.last.last.body)["deal"]
      assert_equal "Lead", deal["name"]
      assert_not deal.key?("amount")
    end
  end

  test "create_deal requires a name" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_deal", { "amount" => "100" }) }
    end
  end

  test "create_deal raises on a non-2xx response" do
    with_http(500) do
      assert_raises(Connectors::Error) { provider.invoke("create_deal", { "name" => "X" }) }
    end
  end

  # --- config / creds / unknown action ---

  test "a missing bundle_domain raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "bundle_domain" => "" }).invoke("create_contact", { "first_name" => "Ada" })
    end
  end

  test "a missing api_key raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_key" => "" }).invoke("create_deal", { "name" => "X" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
