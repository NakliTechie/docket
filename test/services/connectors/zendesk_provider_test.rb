require "test_helper"

# Effector-only Zendesk support provider: open a ticket or append a comment.
# API-token Basic auth ("<email>/token"); base derived from the subdomain.
class Connectors::ZendeskProviderTest < ActiveSupport::TestCase
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
                         config: { "subdomain" => "acme", "email" => "agent@acme.gov" }.merge(config))
    conn.credentials_hash = { "api_token" => "tok_123" }.merge(creds)
    Connectors::ZendeskProvider.new(conn)
  end

  EXPECTED_AUTH = "Basic #{[ 'agent@acme.gov/token:tok_123' ].pack('m0')}".freeze

  # --- descriptor / registration shape ---

  test "declares an effector-only descriptor with subdomain/email config and api_token secret" do
    d = Connectors::ZendeskProvider.descriptor
    assert_equal "zendesk", d.key
    assert_equal "Support & Ticketing", d.category
    assert_not d.syncs?
    assert_equal %w[subdomain email], d.config_fields
    assert_equal %w[api_token], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision classes (citizen-facing support writes need a human) ---

  test "create_ticket is a confirm-class write" do
    assert_equal :confirm, Connectors::ZendeskProvider.action("create_ticket").effective_decision_class
  end

  test "add_comment is a confirm-class write" do
    assert_equal :confirm, Connectors::ZendeskProvider.action("add_comment").effective_decision_class
  end

  # --- create_ticket ---

  test "create_ticket POSTs to tickets.json with Basic auth and the ticket body" do
    with_http(201, '{"ticket":{"id":42,"subject":"Pothole"}}') do |reqs|
      obs = provider.invoke("create_ticket",
                            { "subject" => "Pothole", "body" => "Reported on Main St", "priority" => "high" })
      assert obs["ok"]
      assert_equal 42, obs["ticket"]["ticket"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/api/v2/tickets.json", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]
      assert_equal "application/json", req["Content-Type"]

      payload = JSON.parse(req.body)
      assert_equal "Pothole", payload["ticket"]["subject"]
      assert_equal "Reported on Main St", payload["ticket"]["comment"]["body"]
      assert_equal "high", payload["ticket"]["priority"]
    end
  end

  test "create_ticket omits priority when not supplied" do
    with_http(201, '{"ticket":{"id":7}}') do |reqs|
      provider.invoke("create_ticket", { "subject" => "Hi", "body" => "There" })
      payload = JSON.parse(reqs.last.last.body)
      assert_not payload["ticket"].key?("priority")
    end
  end

  test "create_ticket requires a subject" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_ticket", { "body" => "no subject" }) }
    end
  end

  test "create_ticket requires a body" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_ticket", { "subject" => "no body" }) }
    end
  end

  test "create_ticket raises on a non-2xx response" do
    with_http(422, '{"error":"RecordInvalid"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("create_ticket", { "subject" => "x", "body" => "y" })
      end
    end
  end

  # --- add_comment ---

  test "add_comment PUTs to the ticket with a public comment by default" do
    with_http(200, '{"ticket":{"id":42}}') do |reqs|
      obs = provider.invoke("add_comment", { "ticket_id" => "42", "body" => "Crew dispatched" })
      assert obs["ok"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Put, req
      assert_equal "/api/v2/tickets/42.json", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]

      comment = JSON.parse(req.body)["ticket"]["comment"]
      assert_equal "Crew dispatched", comment["body"]
      assert_equal true, comment["public"]
    end
  end

  test "add_comment honours an explicit internal (non-public) note" do
    with_http(200, "{}") do |reqs|
      provider.invoke("add_comment", { "ticket_id" => "9", "body" => "Internal note", "public" => false })
      comment = JSON.parse(reqs.last.last.body)["ticket"]["comment"]
      assert_equal false, comment["public"]
    end
  end

  test "add_comment requires a ticket_id" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("add_comment", { "body" => "x" }) }
    end
  end

  test "add_comment requires a body" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("add_comment", { "ticket_id" => "1" }) }
    end
  end

  test "add_comment raises on a non-2xx response" do
    with_http(404, '{"error":"NotFound"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("add_comment", { "ticket_id" => "1", "body" => "y" })
      end
    end
  end

  # --- config / unknown action ---

  test "a missing subdomain raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "subdomain" => "" }).invoke("create_ticket", { "subject" => "x", "body" => "y" })
    end
  end

  test "a missing api_token raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_token" => "" }).invoke("create_ticket", { "subject" => "x", "body" => "y" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
