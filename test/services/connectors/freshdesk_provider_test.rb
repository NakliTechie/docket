require "test_helper"

# Effector-only Freshdesk support provider: open a ticket or post a reply.
# API-key Basic auth (api_key as username, literal "X" as password); base
# derived from the account subdomain (https://{domain}.freshdesk.com).
class Connectors::FreshdeskProviderTest < ActiveSupport::TestCase
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
                         config: { "domain" => "acme" }.merge(config))
    conn.credentials_hash = { "api_key" => "key_123" }.merge(creds)
    Connectors::FreshdeskProvider.new(conn)
  end

  EXPECTED_AUTH = "Basic #{[ 'key_123:X' ].pack('m0')}".freeze

  # --- descriptor / registration shape ---

  test "declares an effector-only descriptor with domain config and api_key secret" do
    d = Connectors::FreshdeskProvider.descriptor
    assert_equal "freshdesk", d.key
    assert_equal "Freshdesk (support)", d.name
    assert_equal "Support & Ticketing", d.category
    assert_not d.syncs?
    assert_equal %w[domain], d.config_fields
    assert_equal %w[api_key], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision classes (citizen-facing support writes need a human) ---

  test "create_ticket is a confirm-class write" do
    action = Connectors::FreshdeskProvider.action("create_ticket")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
  end

  test "reply_ticket is a confirm-class write" do
    action = Connectors::FreshdeskProvider.action("reply_ticket")
    assert_equal :write, action.effect
    assert_equal :confirm, action.effective_decision_class
  end

  # --- create_ticket ---

  test "create_ticket POSTs to /api/v2/tickets with Basic auth and the ticket body" do
    with_http(201, '{"id":42,"subject":"Pothole"}') do |reqs|
      obs = provider.invoke("create_ticket",
                            { "subject" => "Pothole", "description" => "Reported on Main St",
                              "email" => "resident@acme.gov", "priority" => 3 })
      assert obs["ok"]
      assert_equal 42, obs["ticket"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/api/v2/tickets", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]
      assert_equal "application/json", req["Content-Type"]

      payload = JSON.parse(req.body)
      assert_equal "Pothole", payload["subject"]
      assert_equal "Reported on Main St", payload["description"]
      assert_equal "resident@acme.gov", payload["email"]
      assert_equal 3, payload["priority"]
      assert_equal 2, payload["status"]
    end
  end

  test "create_ticket defaults priority to 1 when not supplied" do
    with_http(201, '{"id":7}') do |reqs|
      provider.invoke("create_ticket",
                      { "subject" => "Hi", "description" => "There", "email" => "x@acme.gov" })
      payload = JSON.parse(reqs.last.last.body)
      assert_equal 1, payload["priority"]
    end
  end

  test "create_ticket requires a subject" do
    with_http(201) do
      assert_raises(Connectors::Error) do
        provider.invoke("create_ticket", { "description" => "d", "email" => "x@acme.gov" })
      end
    end
  end

  test "create_ticket requires a description" do
    with_http(201) do
      assert_raises(Connectors::Error) do
        provider.invoke("create_ticket", { "subject" => "s", "email" => "x@acme.gov" })
      end
    end
  end

  test "create_ticket requires an email" do
    with_http(201) do
      assert_raises(Connectors::Error) do
        provider.invoke("create_ticket", { "subject" => "s", "description" => "d" })
      end
    end
  end

  test "create_ticket raises on a non-2xx response" do
    with_http(422, '{"errors":[]}') do
      assert_raises(Connectors::Error) do
        provider.invoke("create_ticket", { "subject" => "s", "description" => "d", "email" => "x@acme.gov" })
      end
    end
  end

  # --- reply_ticket ---

  test "reply_ticket POSTs to the ticket reply endpoint with the body" do
    with_http(201, '{"id":99,"ticket_id":42}') do |reqs|
      obs = provider.invoke("reply_ticket", { "ticket_id" => "42", "body" => "Crew dispatched" })
      assert obs["ok"]
      assert_equal 42, obs["reply"]["ticket_id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/api/v2/tickets/42/reply", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]

      payload = JSON.parse(req.body)
      assert_equal "Crew dispatched", payload["body"]
    end
  end

  test "reply_ticket requires a ticket_id" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("reply_ticket", { "body" => "x" }) }
    end
  end

  test "reply_ticket requires a body" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("reply_ticket", { "ticket_id" => "1" }) }
    end
  end

  test "reply_ticket raises on a non-2xx response" do
    with_http(404, '{"error":"NotFound"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("reply_ticket", { "ticket_id" => "1", "body" => "y" })
      end
    end
  end

  # --- config / unknown action ---

  test "a missing domain raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "domain" => "" }).invoke("create_ticket",
                                                  { "subject" => "s", "description" => "d", "email" => "x@acme.gov" })
    end
  end

  test "a missing api_key raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_key" => "" }).invoke("reply_ticket", { "ticket_id" => "1", "body" => "y" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
