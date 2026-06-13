require "test_helper"

class Connectors::ShopifyProviderTest < ActiveSupport::TestCase
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
    with_http_seq([ code, body ]) { |reqs| yield reqs }
  end

  # Serve a sequence of responses — the Nth Net::HTTP.new gets the Nth pair
  # (the last pair repeats if more calls happen). create_fulfillment makes two
  # calls: GET fulfillment_orders, then POST fulfillments.
  def with_http_seq(*responses)
    captured = []
    i = -1
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_a|
      i += 1
      code, body = responses[i] || responses.last
      FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h }
    end
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def provider(config: {}, creds: {})
    conn = Connector.new(provider: "http_json", name: "t",
                         config: { "shop_domain" => "acme.myshopify.com", "api_version" => "2025-01" }.merge(config))
    conn.credentials_hash = { "access_token" => "shpat_token" }.merge(creds)
    Connectors::ShopifyProvider.new(conn)
  end

  FO = { "fulfillment_orders" => [ { "id" => 1122 } ] }.to_json

  # --- descriptor / decision classes ---

  test "descriptor declares e-commerce sync provider with custom-token credential" do
    d = Connectors::ShopifyProvider.descriptor
    assert_equal "shopify", d.key
    assert_equal "E-commerce", d.category
    assert d.syncs?
    assert_equal %w[access_token], d.secret_fields
    assert_equal %w[shop_domain api_version], d.config_fields
  end

  test "create_fulfillment is a confirm action" do
    assert_equal :confirm, Connectors::ShopifyProvider.action("create_fulfillment").effective_decision_class
  end

  test "create_refund is a decision of record (moves money)" do
    action = Connectors::ShopifyProvider.action("create_refund")
    assert_equal :of_record, action.effective_decision_class
    assert action.of_record?
  end

  # --- create_fulfillment (resolves the fulfillment order, then fulfils) ---

  test "create_fulfillment resolves the order's fulfillment orders then posts tracking_info" do
    done = { "fulfillment" => { "id" => 99, "status" => "success" } }.to_json
    with_http_seq([ 200, FO ], [ 201, done ]) do |reqs|
      obs = provider.invoke("create_fulfillment",
                            { "order_id" => "450789469", "tracking_number" => "1Z999", "notify_customer" => true })
      assert obs["ok"]
      assert_equal "success", obs["fulfillment"]["fulfillment"]["status"]

      get = reqs.first.last
      assert_equal "/admin/api/2025-01/orders/450789469/fulfillment_orders.json", get.path
      assert_kind_of Net::HTTP::Get, get

      post = reqs.last.last
      assert_equal "/admin/api/2025-01/fulfillments.json", post.path
      assert_kind_of Net::HTTP::Post, post
      assert_equal "shpat_token", post["X-Shopify-Access-Token"]
      sent = JSON.parse(post.body)["fulfillment"]
      assert_equal [ { "fulfillment_order_id" => 1122 } ], sent["line_items_by_fulfillment_order"]
      assert_equal({ "number" => "1Z999" }, sent["tracking_info"])
      assert_equal true, sent["notify_customer"]
    end
  end

  test "create_fulfillment omits tracking and notify when not given" do
    with_http_seq([ 200, FO ], [ 201, { "fulfillment" => {} }.to_json ]) do |reqs|
      provider.invoke("create_fulfillment", { "order_id" => "1" })
      sent = JSON.parse(reqs.last.last.body)["fulfillment"]
      assert_equal [ { "fulfillment_order_id" => 1122 } ], sent["line_items_by_fulfillment_order"]
      assert_not sent.key?("tracking_info")
      assert_not sent.key?("notify_customer")
    end
  end

  test "create_fulfillment raises when the order has no fulfillment orders" do
    with_http(200, { "fulfillment_orders" => [] }.to_json) do
      assert_raises(Connectors::Error) { provider.invoke("create_fulfillment", { "order_id" => "1" }) }
    end
  end

  test "create_fulfillment requires order_id" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_fulfillment", {}) }
    end
  end

  test "create_fulfillment raises when the fulfillment-order lookup fails" do
    with_http(422, { "errors" => "bad" }.to_json) do
      assert_raises(Connectors::Error) { provider.invoke("create_fulfillment", { "order_id" => "1" }) }
    end
  end

  # --- create_refund ---

  test "create_refund posts to the order refunds endpoint with the note" do
    body = { "refund" => { "id" => 509562969, "note" => "damaged" } }.to_json
    with_http(201, body) do |reqs|
      obs = provider.invoke("create_refund", { "order_id" => "450789469", "note" => "damaged" })
      assert obs["ok"]
      assert_equal "damaged", obs["refund"]["refund"]["note"]

      req = reqs.last.last
      assert_equal "/admin/api/2025-01/orders/450789469/refunds.json", req.path
      assert_kind_of Net::HTTP::Post, req
      assert_equal "shpat_token", req["X-Shopify-Access-Token"]
      assert_equal "damaged", JSON.parse(req.body)["refund"]["note"]
    end
  end

  test "create_refund requires order_id" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "note" => "x" }) }
    end
  end

  test "create_refund raises on a non-2xx response" do
    with_http(404) do
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "order_id" => "1" }) }
    end
  end

  # --- defaults / derivation ---

  test "api_version defaults to 2025-01 when config value is blank" do
    with_http_seq([ 200, FO ], [ 201, { "fulfillment" => {} }.to_json ]) do |reqs|
      provider(config: { "api_version" => "" }).invoke("create_fulfillment", { "order_id" => "1" })
      assert_equal "/admin/api/2025-01/orders/1/fulfillment_orders.json", reqs.first.last.path
      assert_equal "/admin/api/2025-01/fulfillments.json", reqs.last.last.path
    end
  end

  test "a missing shop_domain raises" do
    with_http(201) do
      assert_raises(Connectors::Error) { provider(config: { "shop_domain" => "" }).invoke("create_fulfillment", { "order_id" => "1" }) }
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end

  # --- fetch (sync) ---

  test "fetch returns the customers array" do
    body = { "customers" => [ { "id" => 1, "email" => "a@b.com" }, { "id" => 2 } ] }.to_json
    with_http(200, body) do |reqs|
      records = provider.fetch
      assert_equal 2, records.length
      assert_equal "a@b.com", records.first["email"]

      req = reqs.last.last
      assert_equal "/admin/api/2025-01/customers.json", req.path
      assert_kind_of Net::HTTP::Get, req
      assert_equal "shpat_token", req["X-Shopify-Access-Token"]
    end
  end

  test "fetch raises on a non-2xx response" do
    with_http(401) do
      assert_raises(Connectors::Error) { provider.fetch }
    end
  end
end
