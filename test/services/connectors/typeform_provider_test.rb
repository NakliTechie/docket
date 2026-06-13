require "test_helper"

class Connectors::TypeformProviderTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last, :host, :port
    def initialize(r, host, port) = (@r = r; @host = host; @port = port)
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @r)
  end
  def with_http(code, body = "{}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |host = nil, port = nil|
      FakeHttp.new(FakeResponse.new(code.to_s, body), host, port).tap { |h| captured << h }
    end
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def provider(config: {}, creds: {})
    conn = Connector.new(provider: "http_json", name: "t",
                         config: { "form_id" => "abc123" }.merge(config))
    conn.credentials_hash = { "access_token" => "tfp_token" }.merge(creds)
    Connectors::TypeformProvider.new(conn)
  end

  # --- descriptor ---

  test "descriptor declares a forms sync provider with Bearer credential" do
    d = Connectors::TypeformProvider.descriptor
    assert_equal "typeform", d.key
    assert_equal "Typeform", d.name
    assert_equal "Forms & Surveys", d.category
    assert d.syncs?
    assert_equal %w[access_token], d.secret_fields
    assert_equal %w[form_id base_url], d.config_fields
  end

  # --- sync-only: no actions, no invoke ---

  test "is sync-only with no agent actions" do
    assert_equal [], Connectors::TypeformProvider.actions
  end

  test "invoke is unsupported (inherits the base NotImplementedError)" do
    assert_raises(NotImplementedError) { provider.invoke("anything", {}) }
  end

  # --- fetch (sync) ---

  test "fetch GETs the form responses endpoint with Bearer auth and returns the items array" do
    body = { "items" => [ { "response_id" => "r1" }, { "response_id" => "r2" } ] }.to_json
    with_http(200, body) do |reqs|
      records = provider.fetch
      assert_equal 2, records.length
      assert_equal "r1", records.first["response_id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Get, req
      assert_equal "/forms/abc123/responses", req.path
      assert_equal "Bearer tfp_token", req["Authorization"]
    end
  end

  test "fetch hits the default base host" do
    with_http(200, { "items" => [] }.to_json) do |reqs|
      provider.fetch
      assert_equal "api.typeform.com", reqs.last.host
    end
  end

  test "fetch returns an empty array when the items key is absent" do
    with_http(200, { "total_items" => 0 }.to_json) do
      assert_equal [], provider.fetch
    end
  end

  test "fetch tolerates a non-hash body by returning an empty array" do
    with_http(200, "not json") do
      assert_equal [], provider.fetch
    end
  end

  test "fetch uses the base_url config override when present" do
    with_http(200, { "items" => [] }.to_json) do |reqs|
      provider(config: { "base_url" => "https://eu.typeform.com" }).fetch
      assert_equal "eu.typeform.com", reqs.last.host
      assert_equal "/forms/abc123/responses", reqs.last.last.path
    end
  end

  test "fetch raises when form_id is missing" do
    with_http(200, { "items" => [] }.to_json) do
      assert_raises(Connectors::Error) { provider(config: { "form_id" => "" }).fetch }
    end
  end

  test "fetch raises when the access token is missing" do
    with_http(200, { "items" => [] }.to_json) do
      assert_raises(Connectors::Error) { provider(creds: { "access_token" => "" }).fetch }
    end
  end

  test "fetch raises on a non-2xx response" do
    with_http(401) do
      assert_raises(Connectors::Error) { provider.fetch }
    end
  end
end
