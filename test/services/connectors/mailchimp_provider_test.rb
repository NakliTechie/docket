require "test_helper"

# Effector-only Mailchimp (Marketing v3) provider: subscribe a contact to an
# audience. Basic auth (arbitrary username "docket", api_key as password);
# base derived from the datacenter server_prefix
# (https://{server_prefix}.api.mailchimp.com), list from config.
class Connectors::MailchimpProviderTest < ActiveSupport::TestCase
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
    Net::HTTP.define_singleton_method(:new) { |host, port, *_a| FakeHttp.new(FakeResponse.new(code.to_s, body), host, port).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def provider(config: {}, creds: {})
    conn = Connector.new(provider: "http_json", name: "t",
                         config: { "server_prefix" => "us21", "list_id" => "abc123" }.merge(config))
    conn.credentials_hash = { "api_key" => "key_123" }.merge(creds)
    Connectors::MailchimpProvider.new(conn)
  end

  EXPECTED_AUTH = "Basic #{[ 'docket:key_123' ].pack('m0')}".freeze

  # --- descriptor / registration shape ---

  test "declares an effector-only descriptor with server_prefix + list_id config and api_key secret" do
    d = Connectors::MailchimpProvider.descriptor
    assert_equal "mailchimp", d.key
    assert_equal "Mailchimp (email marketing)", d.name
    assert_equal "Marketing", d.category
    assert_not d.syncs?
    assert_equal %w[server_prefix list_id], d.config_fields
    assert_equal %w[api_key], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision class (marketing contact write needs a human) ---

  test "add_member is a confirm-class write" do
    action = Connectors::MailchimpProvider.action("add_member")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  # --- add_member ---

  test "add_member POSTs to the list members endpoint with Basic auth and the subscriber body" do
    with_http(200, '{"id":"hash","email_address":"resident@acme.gov","status":"subscribed"}') do |reqs|
      obs = provider.invoke("add_member",
                            { "email" => "resident@acme.gov", "first_name" => "Asha", "last_name" => "Rao" })
      assert obs["ok"]
      assert_equal "resident@acme.gov", obs["email"]
      assert_equal "subscribed", obs["member"]["status"]

      assert_equal "us21.api.mailchimp.com", reqs.last.host
      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/3.0/lists/abc123/members", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]
      assert_equal "application/json", req["Content-Type"]

      payload = JSON.parse(req.body)
      assert_equal "resident@acme.gov", payload["email_address"]
      assert_equal "subscribed", payload["status"]
      assert_equal "Asha", payload["merge_fields"]["FNAME"]
      assert_equal "Rao", payload["merge_fields"]["LNAME"]
    end
  end

  test "add_member builds the base host from the server_prefix datacenter" do
    with_http(200) do |reqs|
      provider(config: { "server_prefix" => "us6" }).invoke("add_member", { "email" => "x@acme.gov" })
      assert_equal "us6.api.mailchimp.com", reqs.last.host
    end
  end

  test "add_member omits merge_fields entirely when no name is supplied" do
    with_http(200) do |reqs|
      provider.invoke("add_member", { "email" => "x@acme.gov" })
      payload = JSON.parse(reqs.last.last.body)
      assert_not payload.key?("merge_fields")
      assert_equal "subscribed", payload["status"]
    end
  end

  test "add_member includes only the supplied name as a merge field" do
    with_http(200) do |reqs|
      provider.invoke("add_member", { "email" => "x@acme.gov", "first_name" => "Asha" })
      payload = JSON.parse(reqs.last.last.body)
      assert_equal({ "FNAME" => "Asha" }, payload["merge_fields"])
    end
  end

  test "add_member reads symbol-keyed args defensively" do
    with_http(200) do |reqs|
      provider.invoke("add_member", { email: "sym@acme.gov", first_name: "Sym" })
      payload = JSON.parse(reqs.last.last.body)
      assert_equal "sym@acme.gov", payload["email_address"]
      assert_equal "Sym", payload["merge_fields"]["FNAME"]
    end
  end

  test "add_member requires an email" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("add_member", { "first_name" => "Asha" }) }
    end
  end

  test "add_member raises on a non-2xx response" do
    with_http(400, '{"title":"Member Exists"}') do
      assert_raises(Connectors::Error) { provider.invoke("add_member", { "email" => "x@acme.gov" }) }
    end
  end

  # --- config / creds / unknown action ---

  test "a missing server_prefix raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "server_prefix" => "" }).invoke("add_member", { "email" => "x@acme.gov" })
    end
  end

  test "a missing list_id raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "list_id" => "" }).invoke("add_member", { "email" => "x@acme.gov" })
    end
  end

  test "a missing api_key raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_key" => "" }).invoke("add_member", { "email" => "x@acme.gov" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
