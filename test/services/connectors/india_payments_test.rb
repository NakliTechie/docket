require "test_helper"
require "openssl"

# India payment gateways with checksum auth — PayU (SHA-512 over
# key|command|var1|salt) and PhonePe (X-VERIFY = sha256(path+saltKey)###index).
# The checksum formulas are verified by recomputing them independently in the
# test; the live API contract is still owed a real call (see KNOWN-GAPS).
class Connectors::IndiaPaymentsTest < ActiveSupport::TestCase
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

  def conn(provider, config: {}, creds: {})
    c = Connector.new(name: provider, provider: provider, config: config)
    c.credentials_hash = creds
    c
  end

  # --- PayU ---

  test "payu verify_payment is autonomous; refund is a decision of record" do
    assert_equal :autonomous, Connectors::PayuProvider.action("verify_payment").effective_decision_class
    refund = Connectors::PayuProvider.action("refund_payment")
    assert refund.of_record?
    assert refund.requires_approval?
  end

  test "payu verify_payment posts the SHA-512 checksum over key|command|var1|salt" do
    c = conn("payu", creds: { "merchant_key" => "mkey", "merchant_salt" => "msalt" })
    with_http(200, %({"status":1,"transaction_details":{}})) do |reqs|
      c.provider_instance.invoke("verify_payment", { "txnid" => "txn123" })
      form = URI.decode_www_form(reqs.last.last.body).to_h
      assert_equal "mkey", form["key"]
      assert_equal "verify_payment", form["command"]
      assert_equal "txn123", form["var1"]
      expected = OpenSSL::Digest::SHA512.hexdigest("mkey|verify_payment|txn123|msalt")
      assert_equal expected, form["hash"]
      assert_equal "/merchant/postservice.php?form=2", reqs.last.last.path
    end
  end

  test "payu refund_payment sends the cancel_refund command with its vars + hash" do
    c = conn("payu", creds: { "merchant_key" => "mkey", "merchant_salt" => "msalt" })
    with_http(200, %({"status":1})) do |reqs|
      c.provider_instance.invoke("refund_payment", { "mihpayid" => "PAYU1", "refund_token" => "RT1", "amount" => "100" })
      form = URI.decode_www_form(reqs.last.last.body).to_h
      assert_equal "cancel_refund_transaction", form["command"]
      assert_equal "PAYU1", form["var1"]
      assert_equal "RT1", form["var2"]
      assert_equal "100", form["var3"]
      assert_equal OpenSSL::Digest::SHA512.hexdigest("mkey|cancel_refund_transaction|PAYU1|msalt"), form["hash"]
    end
    assert_raises(Connectors::Error) { c.provider_instance.invoke("refund_payment", { "mihpayid" => "PAYU1" }) }
  end

  # --- PhonePe ---

  test "phonepe check_status sends the X-VERIFY checksum over path+saltKey###index" do
    c = conn("phonepe", config: { "merchant_id" => "MID1", "salt_index" => "2" }, creds: { "salt_key" => "saltsecret" })
    with_http(200, %({"success":true,"code":"PAYMENT_SUCCESS"})) do |reqs|
      obs = c.provider_instance.invoke("check_status", { "transaction_id" => "txn1" })
      assert obs["ok"]
      req = reqs.last.last
      # Full wire path includes the hermes base prefix…
      assert_equal "/apis/hermes/pg/v1/status/MID1/txn1", req.path
      assert_equal "MID1", req["X-Merchant-Id"]
      # …but the X-VERIFY checksum is over the bare endpoint path (per PhonePe docs).
      expected = OpenSSL::Digest::SHA256.hexdigest("/pg/v1/status/MID1/txn1saltsecret") + "###2"
      assert_equal expected, req["X-Verify"]
    end
  end

  test "phonepe defaults the salt index to 1 and requires a transaction_id" do
    c = conn("phonepe", config: { "merchant_id" => "MID1" }, creds: { "salt_key" => "s" })
    with_http(200) do |reqs|
      c.provider_instance.invoke("check_status", { "transaction_id" => "t" })
      assert_match(/###1\z/, reqs.last.last["X-Verify"])
    end
    assert_raises(Connectors::Error) { c.provider_instance.invoke("check_status", {}) }
  end
end
