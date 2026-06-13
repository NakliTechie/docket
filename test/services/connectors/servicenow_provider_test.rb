require "test_helper"

# Effector-only ServiceNow ITSM provider: open an incident via the Table API.
# Basic auth (username:password); base derived from the instance name.
class Connectors::ServicenowProviderTest < ActiveSupport::TestCase
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
                         config: { "instance" => "acme" }.merge(config))
    conn.credentials_hash = { "username" => "svc_bot", "password" => "s3cr3t" }.merge(creds)
    Connectors::ServicenowProvider.new(conn)
  end

  EXPECTED_AUTH = "Basic #{[ 'svc_bot:s3cr3t' ].pack('m0')}".freeze

  # --- descriptor / registration shape ---

  test "declares an effector-only descriptor with instance config and username/password secrets" do
    d = Connectors::ServicenowProvider.descriptor
    assert_equal "servicenow", d.key
    assert_equal "Support & Ticketing", d.category
    assert_not d.syncs?
    assert_equal %w[instance], d.config_fields
    assert_equal %w[username password], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision class (citizen-facing ITSM write needs a human) ---

  test "create_incident is a confirm-class write" do
    assert_equal :confirm, Connectors::ServicenowProvider.action("create_incident").effective_decision_class
  end

  # --- create_incident ---

  test "create_incident POSTs to the incident table with Basic auth and the body" do
    with_http(201, '{"result":{"sys_id":"abc123","number":"INC0010042"}}') do |reqs|
      obs = provider.invoke("create_incident",
                            { "short_description" => "Login outage",
                              "description" => "Users cannot authenticate",
                              "urgency" => "1" })
      assert obs["ok"]
      assert_equal "INC0010042", obs["result"]["result"]["number"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/api/now/table/incident", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]
      assert_equal "application/json", req["Content-Type"]

      payload = JSON.parse(req.body)
      assert_equal "Login outage", payload["short_description"]
      assert_equal "Users cannot authenticate", payload["description"]
      assert_equal "1", payload["urgency"]
    end
  end

  test "create_incident hits the derived per-instance host" do
    with_http(201, '{"result":{}}') do
      uri = nil
      original = Net::HTTP.method(:new)
      Net::HTTP.define_singleton_method(:new) do |host, port|
        uri = [ host, port ]
        FakeHttp.new(FakeResponse.new("201", '{"result":{}}'))
      end
      provider.invoke("create_incident", { "short_description" => "x" })
      assert_equal [ "acme.service-now.com", 443 ], uri
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end
  end

  test "create_incident omits description and urgency when not supplied" do
    with_http(201, '{"result":{"sys_id":"s1"}}') do |reqs|
      provider.invoke("create_incident", { "short_description" => "Only summary" })
      payload = JSON.parse(reqs.last.last.body)
      assert_not payload.key?("description")
      assert_not payload.key?("urgency")
      assert_equal "Only summary", payload["short_description"]
    end
  end

  test "create_incident requires a short_description" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_incident", { "description" => "no summary" }) }
    end
  end

  test "create_incident raises on a non-2xx response" do
    with_http(403, '{"error":{"message":"insufficient rights"}}') do
      assert_raises(Connectors::Error) do
        provider.invoke("create_incident", { "short_description" => "x" })
      end
    end
  end

  # --- config / creds / unknown action ---

  test "a missing instance raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "instance" => "" }).invoke("create_incident", { "short_description" => "x" })
    end
  end

  test "a missing username raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "username" => "" }).invoke("create_incident", { "short_description" => "x" })
    end
  end

  test "a missing password raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "password" => "" }).invoke("create_incident", { "short_description" => "x" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
