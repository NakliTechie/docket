require "test_helper"

# SendGrid transactional email (citizen-facing comms → confirm). Bearer API
# key, POST /v3/mail/send, success is HTTP 202.
class Connectors::SendgridProviderTest < ActiveSupport::TestCase
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
      config: { "from_email" => "noreply@docket.gov" }.merge(config))
    conn.credentials_hash = { "api_key" => "SG.test-key" }.merge(creds)
    Connectors::SendgridProvider.new(conn)
  end

  # --- decision class ---

  test "send_email is a confirm action (citizen-facing email needs review)" do
    assert_equal :confirm, Connectors::SendgridProvider.action("send_email").effective_decision_class
    assert Connectors::SendgridProvider.action("send_email").requires_approval?
  end

  test "sendgrid is declared effector-only and never syncs" do
    assert_not Connectors::SendgridProvider.descriptor.syncs?
    assert_equal [], provider.fetch
  end

  # --- send_email (network stubbed) ---

  test "send_email posts to /v3/mail/send with bearer auth and the v3 mail body" do
    with_http(202, "") do |reqs|
      obs = provider.invoke("send_email",
        { "to" => "asha@example.com", "subject" => "Your case update", "body" => "Hello Asha" })

      assert obs["ok"]
      assert_equal "asha@example.com", obs["to"]
      assert_equal 202, obs["status"]

      req = reqs.last.last
      assert_equal "/v3/mail/send", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "Bearer SG.test-key", req["Authorization"]

      body = JSON.parse(req.body)
      assert_equal "asha@example.com", body["personalizations"][0]["to"][0]["email"]
      assert_equal "noreply@docket.gov", body["from"]["email"]
      assert_equal "Your case update", body["subject"]
      assert_equal "text/plain", body["content"][0]["type"]
      assert_equal "Hello Asha", body["content"][0]["value"]
    end
  end

  test "send_email honours a custom base_url" do
    with_http(202, "") do |reqs|
      obs = provider(config: { "base_url" => "https://eu.api.sendgrid.com" }).invoke(
        "send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
      assert obs["ok"]
      # path stays the same; only the host changes, which build_uri resolves
      # from the configured base_url.
      assert_equal "/v3/mail/send", reqs.last.last.path
    end
  end

  # --- failure modes ---

  test "send_email raises on a non-2xx response" do
    with_http(401, '{"errors":[{"message":"unauthorized"}]}') do
      assert_raises(Connectors::Error) do
        provider.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
      end
    end
  end

  test "send_email requires to, subject and body" do
    assert_raises(Connectors::Error) { provider.invoke("send_email", { "subject" => "s", "body" => "b" }) }
    assert_raises(Connectors::Error) { provider.invoke("send_email", { "to" => "a@b.com", "body" => "b" }) }
    assert_raises(Connectors::Error) { provider.invoke("send_email", { "to" => "a@b.com", "subject" => "s" }) }
  end

  test "send_email requires a configured from_email" do
    no_from = provider
    no_from.connector.config = {}
    assert_raises(Connectors::Error) do
      no_from.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
    end
  end

  test "send_email requires an api_key secret" do
    bare = Connector.new(provider: "http_json", name: "t", config: { "from_email" => "x@y.com" })
    bare.credentials_hash = {}
    p = Connectors::SendgridProvider.new(bare)
    assert_raises(Connectors::Error) do
      p.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
    end
  end

  test "unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
