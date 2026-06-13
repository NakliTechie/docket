require "test_helper"

# The OAuth2 CRM effectors — Salesforce, Zoho CRM, HubSpot (OAuth), Dynamics 365
# — on the Connectors::OauthProvider seam. Each has a provider-specific wrinkle
# the base does not assume: Salesforce/Zoho persist a per-account API host from
# the token response; Zoho uses a Zoho-oauthtoken header; Dynamics builds a
# resource-scoped authorize URL. Token refresh itself is covered by the Google
# Calendar reference test.
class Connectors::CrmOauthProvidersTest < ActiveSupport::TestCase
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

  def conn(provider, config: {}, tokens:)
    c = Connector.create!(name: provider, provider: provider, config: { "client_id" => "cid" }.merge(config))
    c.credentials_hash = { "client_secret" => "sec" }
    c.oauth_tokens = tokens
    c.save!
    c
  end

  # --- Salesforce ---

  test "salesforce writes are confirm and create_record targets the instance_url" do
    assert_equal :confirm, Connectors::SalesforceProvider.action("create_record").effective_decision_class
    c = conn("salesforce", tokens: {
      "access_token" => "tok", "instance_url" => "https://acme.my.salesforce.com",
      "expires_at" => 1.hour.from_now.iso8601
    })
    with_http(201, %({"id":"00Q1","success":true})) do |reqs|
      obs = Connectors::SalesforceProvider.new(c).invoke("create_record",
        { "sobject" => "Lead", "fields" => { "LastName" => "Ada", "Company" => "Acme" } })
      assert obs["ok"]
      assert_equal "00Q1", obs["record"]["id"]
      req = reqs.last.last
      assert_equal "/services/data/v59.0/sobjects/Lead/", req.path
      assert_equal "Bearer tok", req["Authorization"]
      assert_equal "Ada", JSON.parse(req.body)["LastName"]
    end
  end

  test "salesforce update_record PATCHes by id and honours a configured api_version" do
    c = conn("salesforce", config: { "api_version" => "v60.0" }, tokens: {
      "access_token" => "tok", "instance_url" => "https://acme.my.salesforce.com",
      "expires_at" => 1.hour.from_now.iso8601
    })
    with_http(204, "") do |reqs|
      obs = Connectors::SalesforceProvider.new(c).invoke("update_record",
        { "sobject" => "Contact", "id" => "003ABC", "fields" => { "Title" => "CEO" } })
      assert_equal "003ABC", obs["id"]
      req = reqs.last.last
      assert_kind_of Net::HTTP::Patch, req
      assert_equal "/services/data/v60.0/sobjects/Contact/003ABC", req.path
    end
  end

  test "salesforce persists the instance_url from the token exchange" do
    c = conn("salesforce", tokens: {})
    body = { access_token: "ya.sf", refresh_token: "r", instance_url: "https://na1.salesforce.com", expires_in: 3600 }.to_json
    with_http(200, body) do
      Connectors::SalesforceProvider.new(c).exchange_code!("code", redirect_uri: "https://docket.test/cb")
    end
    assert_equal "https://na1.salesforce.com", c.reload.oauth_tokens["instance_url"]
  end

  test "salesforce raises when not yet connected (no instance_url)" do
    c = conn("salesforce", tokens: { "access_token" => "tok", "expires_at" => 1.hour.from_now.iso8601 })
    assert_raises(Connectors::Error) do
      Connectors::SalesforceProvider.new(c).invoke("create_record", { "sobject" => "Lead", "fields" => { "x" => 1 } })
    end
  end

  # --- Zoho CRM ---

  test "zoho uses a Zoho-oauthtoken header and the api_domain host, wrapping data in an array" do
    c = conn("zoho_crm", tokens: {
      "access_token" => "ztok", "api_domain" => "https://www.zohoapis.in",
      "expires_at" => 1.hour.from_now.iso8601
    })
    with_http(201, %({"data":[{"code":"SUCCESS","details":{"id":"55"}}]})) do |reqs|
      obs = Connectors::ZohoCrmProvider.new(c).invoke("create_record",
        { "module" => "Leads", "fields" => { "Last_Name" => "Ada" } })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/crm/v5/Leads", req.path
      assert_equal "Zoho-oauthtoken ztok", req["Authorization"]
      assert_equal [ { "Last_Name" => "Ada" } ], JSON.parse(req.body)["data"]
    end
  end

  test "zoho persists api_domain and requires a module + fields" do
    c = conn("zoho_crm", tokens: {})
    body = { access_token: "zt", refresh_token: "r", api_domain: "https://www.zohoapis.com", expires_in: 3600 }.to_json
    with_http(200, body) do
      Connectors::ZohoCrmProvider.new(c).exchange_code!("code", redirect_uri: "https://docket.test/cb")
    end
    assert_equal "https://www.zohoapis.com", c.reload.oauth_tokens["api_domain"]

    connected = conn("zoho_crm", tokens: { "access_token" => "t", "expires_at" => 1.hour.from_now.iso8601 })
    p = Connectors::ZohoCrmProvider.new(connected)
    assert_raises(Connectors::Error) { p.invoke("create_record", { "fields" => { "x" => 1 } }) }
    assert_raises(Connectors::Error) { p.invoke("create_record", { "module" => "Leads", "fields" => {} }) }
  end

  # --- HubSpot (OAuth) ---

  test "hubspot_oauth create_contact posts properties with a Bearer token" do
    c = conn("hubspot_oauth", tokens: { "access_token" => "htok", "expires_at" => 1.hour.from_now.iso8601 })
    with_http(201, %({"id":"501","properties":{"email":"a@b.com"}})) do |reqs|
      obs = Connectors::HubspotOauthProvider.new(c).invoke("create_contact", { "email" => "a@b.com", "firstname" => "Ada" })
      assert_equal "501", obs["contact"]["id"]
      req = reqs.last.last
      assert_equal "/crm/v3/objects/contacts", req.path
      assert_equal "Bearer htok", req["Authorization"]
      assert_equal "a@b.com", JSON.parse(req.body)["properties"]["email"]
    end
  end

  test "hubspot_oauth is a distinct OAuth provider from the static hubspot one" do
    assert Connectors::HubspotOauthProvider < Connectors::OauthProvider
    assert_not Connectors::HubspotProvider < Connectors::OauthProvider
    assert_equal "hubspot_oauth", Connectors::HubspotOauthProvider.descriptor.key
    assert_raises(Connectors::Error) do
      Connectors::HubspotOauthProvider.new(conn("hubspot_oauth", tokens: { "access_token" => "t", "expires_at" => 1.hour.from_now.iso8601 }))
        .invoke("create_contact", { "firstname" => "NoEmail" })
    end
  end

  # --- Dynamics 365 ---

  test "dynamics create_record posts to the resource_url with return=representation" do
    c = conn("dynamics365", config: { "resource_url" => "https://org.crm.dynamics.com" },
             tokens: { "access_token" => "dtok", "expires_at" => 1.hour.from_now.iso8601 })
    with_http(201, %({"leadid":"abc-123","subject":"New"})) do |reqs|
      obs = Connectors::Dynamics365Provider.new(c).invoke("create_record",
        { "entity_set" => "leads", "fields" => { "subject" => "New", "lastname" => "Ada" } })
      assert_equal "abc-123", obs["record"]["leadid"]
      req = reqs.last.last
      assert_equal "/api/data/v9.2/leads", req.path
      assert_equal "Bearer dtok", req["Authorization"]
      assert_equal "return=representation", req["Prefer"]
    end
  end

  test "dynamics authorize_url builds a resource-scoped .default grant" do
    c = conn("dynamics365", config: { "resource_url" => "https://org.crm.dynamics.com/" }, tokens: {})
    url = Connectors::Dynamics365Provider.authorize_url(c, redirect_uri: "https://docket.test/cb", state: "S")
    q = URI.decode_www_form(URI(url).query).to_h
    assert_equal "https://org.crm.dynamics.com/.default offline_access", q["scope"]
    assert_equal "cid", q["client_id"]
    assert_equal "S", q["state"]
  end

  test "dynamics create_record requires resource_url, entity_set and fields" do
    no_resource = conn("dynamics365", tokens: { "access_token" => "t", "expires_at" => 1.hour.from_now.iso8601 })
    assert_raises(Connectors::Error) do
      Connectors::Dynamics365Provider.new(no_resource).invoke("create_record", { "entity_set" => "leads", "fields" => { "x" => 1 } })
    end
  end
end
