require "test_helper"

# The shared HTTP base for named providers: SSRF-guarded URI build, the
# Net::HTTP call, JSON body, response parsing, and auth/required-field helpers.
class Connectors::HttpProviderTest < ActiveSupport::TestCase
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

  # Minimal subclass exposing the protected helpers for testing.
  class Dummy < Connectors::HttpProvider
    def self.descriptor
      Descriptor.new(key: "dummy_http", name: "Dummy", category: "Generic",
                     auth: :none, config_fields: %w[base_url], credential_fields: %w[token])
    end

    def do_post(path)
      uri = build_uri(require_config("base_url"), path)
      resp = post_json(uri, { a: 1 }, headers: { "Authorization" => bearer(require_secret("token")) })
      ensure_ok!(resp, "Dummy")
      parse_json(resp.body)
    end

    def make_uri(base, path = "") = build_uri(base, path)
    def basic(user, pass) = basic_auth(user, pass)
  end

  def dummy(base: "https://api.example.com")
    conn = Connector.new(provider: "http_json", name: "t", config: { "base_url" => base })
    conn.credentials_hash = { "token" => "sek" }
    Dummy.new(conn)
  end

  test "post_json sends an SSRF-guarded request with a JSON body + auth header" do
    with_http(200, '{"ok":true}') do |reqs|
      out = dummy.do_post("/v1/things")
      assert_equal({ "ok" => true }, out)
      req = reqs.last.last
      assert_equal "application/json", req["Content-Type"]
      assert_equal "Bearer sek", req["Authorization"]
      assert_equal({ "a" => 1 }, JSON.parse(req.body))
    end
  end

  test "ensure_ok! raises Connectors::Error on a non-2xx response" do
    with_http(500, "boom") do
      assert_raises(Connectors::Error) { dummy.do_post("/v1/things") }
    end
  end

  test "build_uri rejects non-http schemes, blocked hosts, and malformed urls" do
    assert_raises(Connectors::Error) { dummy.make_uri("ftp://example.com", "/x") }
    assert_raises(Connectors::Error) { dummy.make_uri("https://127.0.0.1", "/x") }
    assert_raises(Connectors::Error) { dummy.make_uri("http://localhost", "/x") }
    assert_raises(Connectors::Error) { dummy.make_uri("", "/x") }
  end

  test "require_config raises when a needed config value is missing" do
    conn = Connector.new(provider: "http_json", name: "t", config: {})
    assert_raises(Connectors::Error) { Dummy.new(conn).do_post("/x") }
  end

  test "basic_auth encodes user:password" do
    assert_equal "Basic #{[ "u:p" ].pack('m0')}", dummy.basic("u", "p")
  end
end
