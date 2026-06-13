require "test_helper"

class Connectors::WoocommerceProviderTest < ActiveSupport::TestCase
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
                         config: { "store_url" => "https://shop.example.com" }.merge(config))
    conn.credentials_hash = { "consumer_key" => "ck_test", "consumer_secret" => "cs_test" }.merge(creds)
    Connectors::WoocommerceProvider.new(conn)
  end

  def expected_auth
    "Basic " + [ "ck_test:cs_test" ].pack("m0")
  end

  # --- descriptor / decision classes ---

  test "descriptor declares an e-commerce sync provider with the consumer key/secret credential pair" do
    d = Connectors::WoocommerceProvider.descriptor
    assert_equal "woocommerce", d.key
    assert_equal "WooCommerce", d.name
    assert_equal "E-commerce", d.category
    assert d.syncs?
    assert_equal %w[store_url], d.config_fields
    assert_equal %w[consumer_key consumer_secret], d.secret_fields
  end

  test "both writes are confirm actions" do
    assert_equal :confirm, Connectors::WoocommerceProvider.action("update_order_status").effective_decision_class
    assert_equal :confirm, Connectors::WoocommerceProvider.action("create_order_note").effective_decision_class
  end

  # --- update_order_status ---

  test "update_order_status PUTs the status to the order endpoint with basic auth" do
    body = { "id" => 123, "status" => "completed" }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("update_order_status", { "order_id" => "123", "status" => "completed" })
      assert obs["ok"]
      assert_equal "completed", obs["order"]["status"]

      req = reqs.last.last
      assert_equal "/wp-json/wc/v3/orders/123", req.path
      assert_kind_of Net::HTTP::Put, req
      assert_equal expected_auth, req["Authorization"]
      assert_equal "completed", JSON.parse(req.body)["status"]
    end
  end

  test "update_order_status requires order_id" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("update_order_status", { "status" => "completed" }) }
    end
  end

  test "update_order_status requires status" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("update_order_status", { "order_id" => "123" }) }
    end
  end

  test "update_order_status raises on a non-2xx response" do
    with_http(404, { "message" => "no" }.to_json) do
      assert_raises(Connectors::Error) { provider.invoke("update_order_status", { "order_id" => "1", "status" => "x" }) }
    end
  end

  # --- create_order_note ---

  test "create_order_note POSTs the note to the order notes endpoint" do
    body = { "id" => 9, "note" => "packed" }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_order_note",
                            { "order_id" => "123", "note" => "packed", "customer_note" => true })
      assert obs["ok"]
      assert_equal "packed", obs["note"]["note"]

      req = reqs.last.last
      assert_equal "/wp-json/wc/v3/orders/123/notes", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal expected_auth, req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "packed", sent["note"]
      assert_equal true, sent["customer_note"]
    end
  end

  test "create_order_note sends customer_note false when explicitly false" do
    with_http(201, { "id" => 1 }.to_json) do |reqs|
      provider.invoke("create_order_note", { "order_id" => "1", "note" => "internal", "customer_note" => false })
      sent = JSON.parse(reqs.last.last.body)
      assert sent.key?("customer_note")
      assert_equal false, sent["customer_note"]
    end
  end

  test "create_order_note omits customer_note when not given" do
    with_http(201, { "id" => 1 }.to_json) do |reqs|
      provider.invoke("create_order_note", { "order_id" => "1", "note" => "hi" })
      sent = JSON.parse(reqs.last.last.body)
      assert_not sent.key?("customer_note")
    end
  end

  test "create_order_note requires order_id" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_order_note", { "note" => "hi" }) }
    end
  end

  test "create_order_note requires note" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_order_note", { "order_id" => "1" }) }
    end
  end

  test "create_order_note raises on a non-2xx response" do
    with_http(500) do
      assert_raises(Connectors::Error) { provider.invoke("create_order_note", { "order_id" => "1", "note" => "hi" }) }
    end
  end

  # --- config / auth derivation ---

  test "a missing store_url raises" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider(config: { "store_url" => "" }).invoke("update_order_status", { "order_id" => "1", "status" => "x" }) }
    end
  end

  test "a missing consumer_secret raises" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider(creds: { "consumer_secret" => "" }).invoke("update_order_status", { "order_id" => "1", "status" => "x" }) }
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end

  # --- fetch (sync) ---

  test "fetch returns the customers array with basic auth" do
    body = [ { "id" => 1, "email" => "a@b.com" }, { "id" => 2 } ].to_json
    with_http(200, body) do |reqs|
      records = provider.fetch
      assert_equal 2, records.length
      assert_equal "a@b.com", records.first["email"]

      req = reqs.last.last
      assert_equal "/wp-json/wc/v3/customers", req.path
      assert_kind_of Net::HTTP::Get, req
      assert_equal expected_auth, req["Authorization"]
    end
  end

  test "fetch returns an empty array when the body is not an array" do
    with_http(200, { "message" => "ok" }.to_json) do
      assert_equal [], provider.fetch
    end
  end

  test "fetch raises on a non-2xx response" do
    with_http(401) do
      assert_raises(Connectors::Error) { provider.fetch }
    end
  end
end
