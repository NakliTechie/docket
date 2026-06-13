require "test_helper"

class Connectors::CashfreeProviderTest < ActiveSupport::TestCase
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
    conn = Connector.new(provider: "http_json", name: "t", config: {}.merge(config))
    conn.credentials_hash = { "client_id" => "cid_1", "client_secret" => "csec_1" }.merge(creds)
    Connectors::CashfreeProvider.new(conn)
  end

  # --- descriptor / registration shape ---

  test "cashfree is effector-only and declares its secret fields" do
    assert_not Connectors::CashfreeProvider.descriptor.syncs?
    assert_equal %w[client_id client_secret], Connectors::CashfreeProvider.descriptor.secret_fields
    assert_equal %w[base_url api_version], Connectors::CashfreeProvider.descriptor.config_fields
    assert_equal [], provider.fetch
  end

  # --- decision classes ---

  test "fetch_order is autonomous (read-only)" do
    action = Connectors::CashfreeProvider.action("fetch_order")
    assert_equal :autonomous, action.effective_decision_class
    assert_not action.requires_approval?
  end

  test "create_refund is a decision of record (moves money, never auto-approved)" do
    action = Connectors::CashfreeProvider.action("create_refund")
    assert_equal :of_record, action.effective_decision_class
    assert action.of_record?
    assert action.requires_approval?
  end

  # --- fetch_order ---

  test "fetch_order GETs the order with the three x-client headers and returns it" do
    body = { "order_id" => "ord_42", "order_status" => "PAID", "order_amount" => 100.0 }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("fetch_order", { "order_id" => "ord_42" })
      assert obs["ok"]
      assert_equal "PAID", obs["order"]["order_status"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Get, req
      assert_equal "/pg/orders/ord_42", req.path
      assert_equal "cid_1", req["x-client-id"]
      assert_equal "csec_1", req["x-client-secret"]
      assert_equal "2023-08-01", req["x-api-version"]
    end
  end

  test "fetch_order honours a configured api_version and base_url" do
    with_http(200, '{"order_id":"ord_1"}') do |reqs|
      p = provider(config: { "base_url" => "https://sandbox.cashfree.com", "api_version" => "2022-09-01" })
      p.invoke("fetch_order", { "order_id" => "ord_1" })
      req = reqs.last.last
      assert_equal "2022-09-01", req["x-api-version"]
      assert_equal "/pg/orders/ord_1", req.path
    end
  end

  test "fetch_order requires order_id" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("fetch_order", {}) }
    end
  end

  test "fetch_order raises on a non-2xx response" do
    with_http(404, '{"message":"order not found"}') do
      assert_raises(Connectors::Error) { provider.invoke("fetch_order", { "order_id" => "nope" }) }
    end
  end

  # --- create_refund ---

  test "create_refund POSTs a JSON body with refund_amount, refund_id and note" do
    body = { "cf_refund_id" => "1", "refund_status" => "SUCCESS" }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("create_refund", {
        "order_id" => "ord_42", "refund_amount" => 50, "refund_id" => "rf_1", "refund_note" => "duplicate"
      })
      assert obs["ok"]
      assert_equal "SUCCESS", obs["refund"]["refund_status"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/pg/orders/ord_42/refunds", req.path
      assert_match %r{application/json}, req["Content-Type"]
      assert_equal "cid_1", req["x-client-id"]
      assert_equal "csec_1", req["x-client-secret"]

      sent = JSON.parse(req.body)
      assert_equal 50, sent["refund_amount"]
      assert_equal "rf_1", sent["refund_id"]
      assert_equal "duplicate", sent["refund_note"]
    end
  end

  test "create_refund omits refund_note when not given" do
    with_http(200, '{"refund_status":"PENDING"}') do |reqs|
      provider.invoke("create_refund", { "order_id" => "ord_1", "refund_amount" => 10, "refund_id" => "rf_2" })
      sent = JSON.parse(reqs.last.last.body)
      assert_not sent.key?("refund_note")
      assert_equal 10, sent["refund_amount"]
      assert_equal "rf_2", sent["refund_id"]
    end
  end

  test "create_refund requires order_id, refund_amount and refund_id" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "refund_amount" => 10, "refund_id" => "rf" }) }
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "order_id" => "o", "refund_id" => "rf" }) }
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "order_id" => "o", "refund_amount" => 10 }) }
    end
  end

  test "create_refund raises on a non-2xx response" do
    with_http(409, '{"message":"refund already exists"}') do
      assert_raises(Connectors::Error) do
        provider.invoke("create_refund", { "order_id" => "o", "refund_amount" => 10, "refund_id" => "rf" })
      end
    end
  end

  # --- generic guards ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end

  test "a missing client_secret raises" do
    with_http(200) do
      assert_raises(Connectors::Error) do
        provider(creds: { "client_secret" => "" }).invoke("fetch_order", { "order_id" => "ord_1" })
      end
    end
  end
end
