require "test_helper"

class Connectors::JotformProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: { "form_id" => "240010001" }.merge(config))
    conn.credentials_hash = { "api_key" => "jf-secret" }.merge(creds)
    Connectors::JotformProvider.new(conn)
  end

  # --- fetch (syncs) ---

  test "fetch returns the content array of submissions" do
    body = {
      "responseCode" => 200,
      "content" => [
        { "id" => "1", "form_id" => "240010001", "answers" => { "3" => { "answer" => "a@b.com" } } },
        { "id" => "2", "form_id" => "240010001", "answers" => { "3" => { "answer" => "c@d.com" } } }
      ]
    }.to_json
    with_http(200, body) do |reqs|
      records = provider.fetch
      assert_equal 2, records.length
      assert_equal "1", records.first["id"]
      assert_equal "2", records.last["id"]

      req = reqs.last.last
      assert_equal "/form/240010001/submissions", req.path
      assert_kind_of Net::HTTP::Get, req
      assert_equal "jf-secret", req["APIKEY"]
    end
  end

  test "fetch returns an empty array when there are no submissions" do
    with_http(200, %({"responseCode":200,"content":[]})) do |_reqs|
      assert_equal [], provider.fetch
    end
  end

  test "fetch returns an empty array when the content key is absent" do
    with_http(200, %({"responseCode":200})) do |_reqs|
      assert_equal [], provider.fetch
    end
  end

  test "fetch drops non-Hash entries in the content array" do
    with_http(200, %({"content":[{"id":"1"},"junk",null]})) do |_reqs|
      records = provider.fetch
      assert_equal 1, records.length
      assert_equal "1", records.first["id"]
    end
  end

  test "fetch raises on a non-2xx response" do
    with_http(401, %({"responseCode":401,"message":"Invalid API key"})) do |_reqs|
      assert_raises(Connectors::Error) { provider.fetch }
    end
  end

  test "fetch requires the form_id config" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.config = {}
      assert_raises(Connectors::Error) { prov.fetch }
    end
  end

  test "fetch raises when the api_key secret is missing" do
    with_http(200) do |_reqs|
      prov = provider
      prov.connector.credentials_hash = {}
      assert_raises(Connectors::Error) { prov.fetch }
    end
  end

  # --- config: base override ---

  test "a configured base_url is used and the path is unchanged" do
    with_http(200, %({"content":[{"id":"9"}]})) do |reqs|
      prov = provider(config: { "base_url" => "https://eu-api.jotform.com" })
      records = prov.fetch
      assert_equal "9", records.first["id"]
      assert_equal "/form/240010001/submissions", reqs.last.last.path
    end
  end

  # --- descriptor + no actions ---

  test "jotform declares itself as a sync-only forms provider" do
    desc = Connectors::JotformProvider.descriptor
    assert desc.syncs?
    assert_equal "jotform", desc.key
    assert_equal "Forms & Surveys", desc.category
    assert_equal %w[api_key], desc.secret_fields
    assert_equal %w[form_id base_url], desc.config_fields
  end

  test "jotform exposes no agent-callable actions" do
    assert_equal [], Connectors::JotformProvider.actions
  end
end
