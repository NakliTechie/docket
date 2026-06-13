require "test_helper"

# Effector-only Jira Cloud issue provider: create an issue or comment on one.
# Atlassian Cloud Basic auth (email:api_token); base derived from the site;
# REST API v2 (plain text). project_key comes from config.
class Connectors::JiraProviderTest < ActiveSupport::TestCase
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
                         config: { "site" => "acme", "email" => "agent@acme.gov", "project_key" => "OPS" }.merge(config))
    conn.credentials_hash = { "api_token" => "tok_123" }.merge(creds)
    Connectors::JiraProvider.new(conn)
  end

  EXPECTED_AUTH = "Basic #{[ 'agent@acme.gov:tok_123' ].pack('m0')}".freeze

  # --- descriptor / registration shape ---

  test "declares an effector-only descriptor with site/email/project_key config and api_token secret" do
    d = Connectors::JiraProvider.descriptor
    assert_equal "jira", d.key
    assert_equal "Support & Ticketing", d.category
    assert_not d.syncs?
    assert_equal %w[site email project_key], d.config_fields
    assert_equal %w[api_token], d.secret_fields
  end

  test "is effector-only: inherited fetch returns an empty array" do
    assert_equal [], provider.fetch
  end

  # --- decision classes (project-backlog writes need a human) ---

  test "create_issue is a confirm-class write" do
    assert_equal :confirm, Connectors::JiraProvider.action("create_issue").effective_decision_class
  end

  test "add_comment is a confirm-class write" do
    assert_equal :confirm, Connectors::JiraProvider.action("add_comment").effective_decision_class
  end

  # --- create_issue ---

  test "create_issue POSTs to the v2 issue endpoint with Basic auth and the fields body" do
    with_http(201, '{"id":"10001","key":"OPS-42"}') do |reqs|
      obs = provider.invoke("create_issue",
                            { "summary" => "Pothole on Main St", "description" => "Reported by resident",
                              "issue_type" => "Bug" })
      assert obs["ok"]
      assert_equal "OPS-42", obs["result"]["key"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/rest/api/2/issue", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]
      assert_equal "application/json", req["Content-Type"]

      fields = JSON.parse(req.body)["fields"]
      assert_equal "OPS", fields["project"]["key"]
      assert_equal "Pothole on Main St", fields["summary"]
      assert_equal "Reported by resident", fields["description"]
      assert_equal "Bug", fields["issuetype"]["name"]
    end
  end

  test "create_issue defaults the issue type to Task and omits an absent description" do
    with_http(201, '{"key":"OPS-7"}') do |reqs|
      provider.invoke("create_issue", { "summary" => "Just a summary" })
      fields = JSON.parse(reqs.last.last.body)["fields"]
      assert_equal "Task", fields["issuetype"]["name"]
      assert_not fields.key?("description")
    end
  end

  test "create_issue requires a summary" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_issue", { "description" => "no summary" }) }
    end
  end

  test "create_issue raises on a non-2xx response" do
    with_http(400, '{"errorMessages":["Invalid"]}') do
      assert_raises(Connectors::Error) { provider.invoke("create_issue", { "summary" => "x" }) }
    end
  end

  # --- add_comment ---

  test "add_comment POSTs the plain-text body to the issue comment endpoint" do
    with_http(201, '{"id":"500","body":"Crew dispatched"}') do |reqs|
      obs = provider.invoke("add_comment", { "issue_key" => "OPS-42", "body" => "Crew dispatched" })
      assert obs["ok"]
      assert_equal "500", obs["result"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert_equal "/rest/api/2/issue/OPS-42/comment", req.path
      assert_equal EXPECTED_AUTH, req["Authorization"]

      assert_equal "Crew dispatched", JSON.parse(req.body)["body"]
    end
  end

  test "add_comment requires an issue_key" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("add_comment", { "body" => "x" }) }
    end
  end

  test "add_comment requires a body" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("add_comment", { "issue_key" => "OPS-1" }) }
    end
  end

  test "add_comment raises on a non-2xx response" do
    with_http(404, '{"errorMessages":["Issue does not exist"]}') do
      assert_raises(Connectors::Error) do
        provider.invoke("add_comment", { "issue_key" => "OPS-1", "body" => "y" })
      end
    end
  end

  # --- config / unknown action ---

  test "a missing site raises before any request" do
    assert_raises(Connectors::Error) do
      provider(config: { "site" => "" }).invoke("create_issue", { "summary" => "x" })
    end
  end

  test "a missing project_key raises before the request" do
    assert_raises(Connectors::Error) do
      provider(config: { "project_key" => "" }).invoke("create_issue", { "summary" => "x" })
    end
  end

  test "a missing api_token raises" do
    assert_raises(Connectors::Error) do
      provider(creds: { "api_token" => "" }).invoke("create_issue", { "summary" => "x" })
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_everything", {}) }
  end
end
