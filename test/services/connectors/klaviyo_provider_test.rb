require "test_helper"

class Connectors::KlaviyoProviderTest < ActiveSupport::TestCase
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
    conn.credentials_hash = { "api_key" => "pk_secret" }.merge(creds)
    Connectors::KlaviyoProvider.new(conn)
  end

  # --- create_profile ---

  test "create_profile posts a JSON:API profile and returns the created record" do
    body = { "data" => { "type" => "profile", "id" => "01H", "attributes" => { "email" => "a@b.com" } } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_profile",
                            { "email" => "a@b.com", "first_name" => "Ada",
                              "last_name" => "Lovelace", "phone_number" => "+15550001" })
      assert obs["ok"]
      assert_equal "01H", obs["result"]["data"]["id"]

      req = reqs.last.last
      assert_equal "/api/profiles", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Klaviyo-API-Key pk_secret", req["Authorization"]
      assert_equal "2024-10-15", req["revision"]
      sent = JSON.parse(req.body)
      assert_equal "profile", sent["data"]["type"]
      attrs = sent["data"]["attributes"]
      assert_equal "a@b.com", attrs["email"]
      assert_equal "Ada", attrs["first_name"]
      assert_equal "Lovelace", attrs["last_name"]
      assert_equal "+15550001", attrs["phone_number"]
    end
  end

  test "create_profile omits optional attributes that were not supplied" do
    with_http(201, %({"data":{"id":"1","type":"profile"}})) do |reqs|
      provider.invoke("create_profile", { "email" => "a@b.com" })
      attrs = JSON.parse(reqs.last.last.body)["data"]["attributes"]
      assert_equal "a@b.com", attrs["email"]
      assert_not attrs.key?("first_name")
      assert_not attrs.key?("last_name")
      assert_not attrs.key?("phone_number")
    end
  end

  test "create_profile accepts symbol-keyed args" do
    with_http(201, %({"data":{"id":"1","type":"profile"}})) do |reqs|
      provider.invoke("create_profile", { email: "a@b.com", first_name: "Ada" })
      attrs = JSON.parse(reqs.last.last.body)["data"]["attributes"]
      assert_equal "a@b.com", attrs["email"]
      assert_equal "Ada", attrs["first_name"]
    end
  end

  test "create_profile requires email" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_profile", { "first_name" => "Ada" }) }
    end
  end

  test "create_profile treats a blank email as missing" do
    with_http(201) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_profile", { "email" => "  " }) }
    end
  end

  test "create_profile raises on a non-2xx response" do
    with_http(400, %({"errors":[{"code":"invalid"}]})) do |_reqs|
      assert_raises(Connectors::Error) { provider.invoke("create_profile", { "email" => "a@b.com" }) }
    end
  end

  test "create_profile raises when the api_key secret is missing" do
    with_http(201) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.invoke("create_profile", { "email" => "a@b.com" }) }
    end
  end

  # --- config ---

  test "a configured base_url is accepted and the action still succeeds" do
    with_http(201, %({"data":{"id":"1","type":"profile"}})) do |reqs|
      prov = provider(config: { "base_url" => "https://a.eu.klaviyo.com" })
      obs = prov.invoke("create_profile", { "email" => "a@b.com" })
      assert obs["ok"]
      # The path is unchanged; only the (stubbed) host differs from the default.
      assert_equal "/api/profiles", reqs.last.last.path
    end
  end

  test "the revision header can be overridden via config" do
    with_http(201, %({"data":{"id":"1","type":"profile"}})) do |reqs|
      prov = provider(config: { "revision" => "2023-10-15" })
      prov.invoke("create_profile", { "email" => "a@b.com" })
      assert_equal "2023-10-15", reqs.last.last["revision"]
    end
  end

  # --- unknown action ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end

  # --- descriptor + decision class ---

  test "create_profile is a confirm-class write" do
    assert_equal :write, Connectors::KlaviyoProvider.action("create_profile").effect
    assert_equal :confirm, Connectors::KlaviyoProvider.action("create_profile").effective_decision_class
  end

  test "klaviyo declares itself as an effector-only marketing provider" do
    desc = Connectors::KlaviyoProvider.descriptor
    assert_equal "klaviyo", desc.key
    assert_equal "Marketing", desc.category
    assert_not desc.syncs?
    assert_equal %w[api_key], desc.secret_fields
    assert_equal %w[base_url revision], desc.config_fields
  end

  test "fetch returns no records for this effector-only provider" do
    assert_equal [], provider.fetch
  end
end
