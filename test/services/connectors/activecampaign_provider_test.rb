require "test_helper"

# Effector-only ActiveCampaign (Marketing v3) provider: create a contact.
# Auth is the Api-Token header carrying the vaulted account token; the base is
# the per-account API URL the admin supplies (https://youraccount.api-us1.com).
class Connectors::ActivecampaignProviderTest < ActiveSupport::TestCase
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
                         config: { "api_url" => "https://acme.api-us1.com" }.merge(config))
    conn.credentials_hash = { "api_token" => "tok_123" }.merge(creds)
    Connectors::ActivecampaignProvider.new(conn)
  end

  # --- descriptor / registration shape ---

  test "declares an effector-only Marketing descriptor with api_url config and api_token secret" do
    d = Connectors::ActivecampaignProvider.descriptor
    assert_equal "activecampaign", d.key
    assert_equal "ActiveCampaign", d.name
    assert_equal "Marketing", d.category
    assert_not d.syncs?
    assert_equal %w[api_url], d.config_fields
    assert_equal %w[api_token], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision class (a marketing write a human confirms) ---

  test "create_contact is a confirm-class write" do
    action = Connectors::ActivecampaignProvider.action("create_contact")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
  end

  # --- create_contact ---

  test "create_contact POSTs to /api/3/contacts with the Api-Token header and nested contact body" do
    with_http(201, '{"contact":{"id":"42","email":"ada@acme.com"}}') do |reqs|
      obs = provider.invoke("create_contact",
                            { "email" => "ada@acme.com", "firstName" => "Ada",
                              "lastName" => "Lovelace", "phone" => "+15551234" })
      assert obs["ok"]
      assert_equal "42", obs["result"]["contact"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/api/3/contacts", req.path
      assert_equal "tok_123", req["Api-Token"]
      assert_equal "application/json", req["Content-Type"]

      contact = JSON.parse(req.body)["contact"]
      assert_equal "ada@acme.com", contact["email"]
      assert_equal "Ada", contact["firstName"]
      assert_equal "Lovelace", contact["lastName"]
      assert_equal "+15551234", contact["phone"]
    end
  end

  test "create_contact omits optional fields that were not supplied" do
    with_http(201, '{"contact":{"id":"7"}}') do |reqs|
      provider.invoke("create_contact", { "email" => "solo@acme.com" })
      contact = JSON.parse(reqs.last.last.body)["contact"]
      assert_equal "solo@acme.com", contact["email"]
      assert_not contact.key?("firstName")
      assert_not contact.key?("lastName")
      assert_not contact.key?("phone")
    end
  end

  test "create_contact accepts symbol-keyed args" do
    with_http(201, '{"contact":{"id":"8"}}') do |reqs|
      provider.invoke("create_contact", { email: "sym@acme.com", firstName: "Sym" })
      contact = JSON.parse(reqs.last.last.body)["contact"]
      assert_equal "sym@acme.com", contact["email"]
      assert_equal "Sym", contact["firstName"]
    end
  end

  test "create_contact requires an email" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "firstName" => "Ada" }) }
    end
  end

  test "create_contact raises on a non-2xx response" do
    with_http(422, '{"errors":[]}') do
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "email" => "ada@acme.com" }) }
    end
  end

  # --- config / creds / unknown action ---

  test "a missing api_url raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "api_url" => "" }).invoke("create_contact", { "email" => "ada@acme.com" })
    end
  end

  test "a missing api_token raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_token" => "" }).invoke("create_contact", { "email" => "ada@acme.com" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
