require "test_helper"

# Mailgun transactional email (citizen-facing comms → confirm). Basic auth
# "api":api_key, POST /v3/{domain}/messages, form-encoded body. domain + from
# come from operator config; EU operators override base_url.
class Connectors::MailgunProviderTest < ActiveSupport::TestCase
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
      config: { "domain" => "mg.docket.gov", "from" => "noreply@docket.gov" }.merge(config))
    conn.credentials_hash = { "api_key" => "key-test" }.merge(creds)
    Connectors::MailgunProvider.new(conn)
  end

  # --- decision class ---

  test "send_email is a confirm action (citizen-facing email needs review)" do
    assert_equal :confirm, Connectors::MailgunProvider.action("send_email").effective_decision_class
    assert Connectors::MailgunProvider.action("send_email").requires_approval?
  end

  test "mailgun is declared effector-only and never syncs" do
    assert_not Connectors::MailgunProvider.descriptor.syncs?
    assert_equal [], provider.fetch
  end

  # --- send_email (network stubbed) ---

  test "send_email posts a form to /v3/{domain}/messages with basic api auth" do
    with_http(200, '{"id":"<msg-1@mg.docket.gov>","message":"Queued. Thank you."}') do |reqs|
      obs = provider.invoke("send_email",
        { "to" => "asha@example.com", "subject" => "Your case update", "body" => "Hello Asha" })

      assert obs["ok"]
      assert_equal "asha@example.com", obs["to"]
      assert_equal "Your case update", obs["subject"]
      assert_equal "Queued. Thank you.", obs["result"]["message"]

      req = reqs.last.last
      assert_equal "/v3/mg.docket.gov/messages", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal basic_auth_header("api", "key-test"), req["Authorization"]
      assert_equal "application/x-www-form-urlencoded", req["Content-Type"]

      form = URI.decode_www_form(req.body).to_h
      assert_equal "noreply@docket.gov", form["from"]
      assert_equal "asha@example.com", form["to"]
      assert_equal "Your case update", form["subject"]
      assert_equal "Hello Asha", form["text"]
    end
  end

  test "send_email honours a custom base_url (EU region)" do
    with_http(200) do |reqs|
      obs = provider(config: { "base_url" => "https://api.eu.mailgun.net" }).invoke(
        "send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
      assert obs["ok"]
      # path stays the same; only the host changes, resolved from base_url.
      assert_equal "/v3/mg.docket.gov/messages", reqs.last.last.path
    end
  end

  # --- failure modes ---

  test "send_email raises on a non-2xx response" do
    with_http(401, '{"message":"Invalid private key"}') do
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

  test "send_email requires a configured domain" do
    p = provider
    p.connector.config = { "from" => "noreply@docket.gov" }
    assert_raises(Connectors::Error) do
      p.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
    end
  end

  test "send_email requires a configured from" do
    p = provider
    p.connector.config = { "domain" => "mg.docket.gov" }
    assert_raises(Connectors::Error) do
      p.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
    end
  end

  test "send_email requires an api_key secret" do
    bare = Connector.new(provider: "http_json", name: "t",
      config: { "domain" => "mg.docket.gov", "from" => "x@y.com" })
    bare.credentials_hash = {}
    p = Connectors::MailgunProvider.new(bare)
    assert_raises(Connectors::Error) do
      p.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
    end
  end

  test "unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end

  private

  def basic_auth_header(user, password)
    "Basic " + [ "#{user}:#{password}" ].pack("m0")
  end
end
