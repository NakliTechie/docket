require "test_helper"

# Trello — effector-only. The API key + token AND every action param ride in
# the QUERY STRING, not headers or a body; the request body is empty JSON. So
# the path assertion (which carries the query string) is the auth assertion
# here. Creating a card is a discretionary write → :confirm.
class Connectors::TrelloProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: { "id_list" => "list_abc" }.merge(config))
    conn.credentials_hash = { "key" => "appkey123", "token" => "usertoken456" }.merge(creds)
    Connectors::TrelloProvider.new(conn)
  end

  # --- decision class ---

  test "create_card is a discretionary write → confirm" do
    assert_equal :confirm, Connectors::TrelloProvider.action("create_card").effective_decision_class
    assert Connectors::TrelloProvider.action("create_card").requires_approval?
  end

  # --- create_card ---

  test "create_card POSTs to /1/cards with auth + params in the query string and an empty JSON body" do
    with_http(200, '{"id":"card789","name":"Follow up","idList":"list_abc"}') do |reqs|
      obs = provider.invoke("create_card", { "name" => "Follow up", "desc" => "Ring the customer" })
      assert obs["ok"]
      assert_equal "card789", obs["result"]["id"]

      req = reqs.last.last
      assert_instance_of Net::HTTP::Post, req
      assert req.path.start_with?("/1/cards?"), "expected /1/cards path, got #{req.path}"

      query = Hash[URI.decode_www_form(req.path.split("?", 2).last)]
      assert_equal "appkey123", query["key"]
      assert_equal "usertoken456", query["token"]
      assert_equal "list_abc", query["idList"]
      assert_equal "Follow up", query["name"]
      assert_equal "Ring the customer", query["desc"]

      # Auth + params are in the query string, never an Authorization header.
      assert_nil req["Authorization"]
      # Empty JSON body.
      assert_equal({}, JSON.parse(req.body))
    end
  end

  test "create_card defaults desc to an empty string when omitted" do
    with_http(200, '{"id":"card789"}') do |reqs|
      provider.invoke("create_card", { "name" => "No desc" })
      query = Hash[URI.decode_www_form(reqs.last.last.path.split("?", 2).last)]
      assert_equal "", query["desc"]
      assert_equal "No desc", query["name"]
    end
  end

  test "create_card honours a custom base_url" do
    with_http(200, '{"id":"card789"}') do |reqs|
      prov = provider(config: { "base_url" => "https://trello.example.com" })
      obs = prov.invoke("create_card", { "name" => "hi" })
      assert obs["ok"]
      assert reqs.last.last.path.start_with?("/1/cards?")
    end
  end

  test "a non-2xx response raises Connectors::Error" do
    with_http(401, '{"message":"unauthorized"}') do
      assert_raises(Connectors::Error) { provider.invoke("create_card", { "name" => "hi" }) }
    end
  end

  test "missing name raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("create_card", { "desc" => "x" }) }
  end

  test "missing id_list config raises Connectors::Error" do
    prov = provider(config: { "id_list" => "" })
    assert_raises(Connectors::Error) { prov.invoke("create_card", { "name" => "hi" }) }
  end

  test "missing key credential raises Connectors::Error" do
    prov = provider(creds: { "key" => "" })
    assert_raises(Connectors::Error) { prov.invoke("create_card", { "name" => "hi" }) }
  end

  test "missing token credential raises Connectors::Error" do
    prov = provider(creds: { "token" => "" })
    assert_raises(Connectors::Error) { prov.invoke("create_card", { "name" => "hi" }) }
  end

  test "an unknown action raises Connectors::Error" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end
end
