require "test_helper"

class Connectors::IntercomProviderTest < ActiveSupport::TestCase
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
    conn.credentials_hash = { "access_token" => "intercom-secret" }.merge(creds)
    Connectors::IntercomProvider.new(conn)
  end

  # --- create_contact ---

  test "create_contact posts a user role contact and returns the created record" do
    body = { "type" => "contact", "id" => "5ba", "role" => "user", "email" => "a@b.com" }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("create_contact",
                            { "email" => "a@b.com", "name" => "Ada", "phone" => "+15550001" })
      assert obs["ok"]
      assert_equal "5ba", obs["contact"]["id"]

      req = reqs.last.last
      assert_equal "/contacts", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Bearer intercom-secret", req["Authorization"]
      assert_equal "2.11", req["Intercom-Version"]
      sent = JSON.parse(req.body)
      assert_equal "user", sent["role"]
      assert_equal "a@b.com", sent["email"]
      assert_equal "Ada", sent["name"]
      assert_equal "+15550001", sent["phone"]
    end
  end

  test "create_contact omits optional fields that were not supplied" do
    with_http(200, %({"id":"1","email":"a@b.com"})) do |reqs|
      provider.invoke("create_contact", { "email" => "a@b.com" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "user", sent["role"]
      assert_equal "a@b.com", sent["email"]
      assert_not sent.key?("name")
      assert_not sent.key?("phone")
    end
  end

  test "create_contact accepts symbol-keyed args" do
    with_http(200, %({"id":"1","email":"a@b.com"})) do |reqs|
      provider.invoke("create_contact", { email: "a@b.com", name: "Ada" })
      sent = JSON.parse(reqs.last.last.body)
      assert_equal "a@b.com", sent["email"]
      assert_equal "Ada", sent["name"]
    end
  end

  test "create_contact requires email" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "name" => "Ada" }) }
    end
  end

  test "create_contact treats a blank email as missing" do
    with_http(200) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "email" => "  " }) }
    end
  end

  test "create_contact raises on a non-2xx response" do
    with_http(401, %({"type":"error.list"})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_contact", { "email" => "a@b.com" }) }
    end
  end

  test "create_contact raises when the access_token secret is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_contact", { "email" => "a@b.com" }) }
    end
  end

  # --- config ---

  test "a configured base_url is accepted and the action still succeeds" do
    with_http(200, %({"id":"1","email":"a@b.com"})) do |reqs|
      prov = provider(config: { "base_url" => "https://api.eu.intercom.io" })
      obs = prov.invoke("create_contact", { "email" => "a@b.com" })
      assert obs["ok"]
      # The path is unchanged; only the (stubbed) host differs from the default.
      assert_equal "/contacts", reqs.last.last.path
    end
  end

  test "the Intercom-Version header can be overridden via config" do
    with_http(200, %({"id":"1","email":"a@b.com"})) do |reqs|
      prov = provider(config: { "intercom_version" => "2.10" })
      prov.invoke("create_contact", { "email" => "a@b.com" })
      assert_equal "2.10", reqs.last.last["Intercom-Version"]
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_contact is a confirm-class write" do
    assert_equal :write, Connectors::IntercomProvider.action("create_contact").effect
    assert_equal :confirm, Connectors::IntercomProvider.action("create_contact").effective_decision_class
  end

  test "intercom declares itself as an effector-only support provider" do
    desc = Connectors::IntercomProvider.descriptor
    assert_equal "intercom", desc.key
    assert_equal "Support & Ticketing", desc.category
    assert_not desc.syncs?
    assert_equal %w[access_token], desc.secret_fields
    assert_equal %w[base_url], desc.config_fields
  end

  test "fetch returns no records for this effector-only provider" do
    assert_equal [], provider.fetch
  end
end
