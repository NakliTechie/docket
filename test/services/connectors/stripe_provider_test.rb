require "test_helper"

class Connectors::StripeProviderTest < ActiveSupport::TestCase
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
    conn.credentials_hash = { "secret_key" => "sk_test_123" }.merge(creds)
    Connectors::StripeProvider.new(conn)
  end

  # --- descriptor / registration shape ---

  test "stripe is effector-only and declares its secret field" do
    assert_not Connectors::StripeProvider.descriptor.syncs?
    assert_equal %w[secret_key], Connectors::StripeProvider.descriptor.secret_fields
    assert_equal [], provider.fetch
  end

  # --- decision classes ---

  test "fetch_payment_intent is autonomous (read-only)" do
    action = Connectors::StripeProvider.action("fetch_payment_intent")
    assert_equal :autonomous, action.effective_decision_class
    assert_not action.requires_approval?
  end

  test "create_refund is a decision of record (moves money, never auto-approved)" do
    action = Connectors::StripeProvider.action("create_refund")
    assert_equal :of_record, action.effective_decision_class
    assert action.of_record?
    assert action.requires_approval?
  end

  # --- fetch_payment_intent ---

  test "fetch_payment_intent GETs the payment intent with bearer auth and returns it" do
    body = { "id" => "pi_123", "amount" => 2000, "status" => "succeeded" }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("fetch_payment_intent", { "payment_intent_id" => "pi_123" })
      assert obs["ok"]
      assert_equal "succeeded", obs["payment_intent"]["status"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Get, req
      assert_equal "/v1/payment_intents/pi_123", req.path
      assert_equal "Bearer sk_test_123", req["Authorization"]
    end
  end

  test "fetch_payment_intent requires payment_intent_id" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("fetch_payment_intent", {}) }
    end
  end

  test "fetch_payment_intent raises on a non-2xx response" do
    with_http(404, '{"error":{"message":"No such payment_intent"}}') do
      assert_raises(Connectors::Error) { provider.invoke("fetch_payment_intent", { "payment_intent_id" => "pi_x" }) }
    end
  end

  # --- create_refund ---

  test "create_refund POSTs a form-encoded body with payment_intent and amount" do
    body = { "id" => "re_1", "status" => "succeeded", "amount" => 500 }.to_json
    with_http(200, body) do |reqs|
      obs = provider.invoke("create_refund", { "payment_intent_id" => "pi_123", "amount" => 500 })
      assert obs["ok"]
      assert_equal "succeeded", obs["refund"]["status"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/v1/refunds", req.path
      assert_equal "Bearer sk_test_123", req["Authorization"]
      assert_match %r{application/x-www-form-urlencoded}, req["Content-Type"]

      form = URI.decode_www_form(req.body).to_h
      assert_equal "pi_123", form["payment_intent"]
      assert_equal "500", form["amount"]
    end
  end

  test "create_refund omits amount when not given (full refund)" do
    with_http(200, '{"id":"re_2","status":"succeeded"}') do |reqs|
      provider.invoke("create_refund", { "payment_intent_id" => "pi_123" })
      form = URI.decode_www_form(reqs.last.last.body).to_h
      assert_equal "pi_123", form["payment_intent"]
      assert_not form.key?("amount")
    end
  end

  test "create_refund requires payment_intent_id" do
    with_http(200) do
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "amount" => 100 }) }
    end
  end

  test "create_refund raises on a non-2xx response" do
    with_http(402, '{"error":{"message":"charge already refunded"}}') do
      assert_raises(Connectors::Error) { provider.invoke("create_refund", { "payment_intent_id" => "pi_123" }) }
    end
  end

  # --- generic guards ---

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("nope", {}) }
  end

  test "a missing secret_key raises" do
    with_http(200) do
      assert_raises(Connectors::Error) do
        provider(creds: { "secret_key" => "" }).invoke("fetch_payment_intent", { "payment_intent_id" => "pi_1" })
      end
    end
  end
end
