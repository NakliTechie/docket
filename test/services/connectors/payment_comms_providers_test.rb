require "test_helper"

# MSG91 (citizen SMS — confirm) and Razorpay (payment read — autonomous;
# refund — of_record). The easy batch, showcasing the decision-class range.
class Connectors::PaymentCommsProvidersTest < ActiveSupport::TestCase
  # --- capturing HTTP stub ---
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

  # --- catalogue ---

  test "the registry offers the connector catalogue with well-formed descriptors" do
    keys = Connectors::Registry.keys
    %w[http_json slack_webhook msg91 razorpay whatsapp_cloud shopify stripe hubspot].each do |k|
      assert_includes keys, k
    end
    assert_operator Connectors::Registry.descriptors.size, :>=, 12

    # Every registered provider exposes a descriptor whose key matches its
    # registry key (catches copy-paste drift) and a human name.
    Connectors::Registry.providers.each do |key, klass|
      assert_equal key, klass.descriptor.key, "registry key #{key} != #{klass}.descriptor.key"
      assert klass.descriptor.name.present?, "#{key} descriptor missing a name"
    end
  end

  # --- MSG91 (citizen comms → confirm) ---

  def msg91
    conn = Connector.create!(name: "Citizen SMS", provider: "msg91",
      config: { "template_id" => "T123", "sender_id" => "DOCKET" })
    conn.credentials_hash = { "authkey" => "secret-key" }
    conn.save!
    conn
  end

  test "msg91 send_sms is a confirm action (citizen-facing comms need review)" do
    assert_equal :confirm, Connectors::Msg91Provider.action("send_sms").effective_decision_class
  end

  test "msg91 send_sms posts to the flow endpoint with the authkey header and template" do
    conn = msg91
    with_http(200, '{"type":"success"}') do |reqs|
      obs = conn.provider_instance.invoke("send_sms", { "mobile" => "+919900000001", "variables" => { "name" => "Asha" } })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "secret-key", req["authkey"]
      assert_equal "T123", JSON.parse(req.body)["template_id"]
    end
  end

  test "msg91 send_sms requires a mobile and a template_id" do
    assert_raises(Connectors::Error) { msg91.provider_instance.invoke("send_sms", {}) }
    bare = Connector.create!(name: "No template", provider: "msg91")
    bare.credentials_hash = { "authkey" => "k" }; bare.save!
    assert_raises(Connectors::Error) { bare.provider_instance.invoke("send_sms", { "mobile" => "+910000000000" }) }
  end

  # --- Razorpay (read autonomous, refund of_record) ---

  def razorpay
    conn = Connector.create!(name: "Refunds", provider: "razorpay")
    conn.credentials_hash = { "key_id" => "rzp_test_1", "key_secret" => "shh" }
    conn.save!
    conn
  end

  test "razorpay reads run autonomously; refunds are decisions of record" do
    assert_equal :autonomous, Connectors::RazorpayProvider.action("fetch_payment").effective_decision_class
    refund = Connectors::RazorpayProvider.action("refund_payment")
    assert refund.of_record?
    assert refund.requires_approval?
  end

  test "razorpay fetch_payment GETs the payment with basic auth" do
    conn = razorpay
    with_http(200, '{"id":"pay_1","status":"captured"}') do |reqs|
      obs = conn.provider_instance.invoke("fetch_payment", { "payment_id" => "pay_1" })
      assert_equal "captured", obs["payment"]["status"]
      assert_match(/\ABasic /, reqs.last.last["Authorization"])
    end
  end

  test "razorpay refund_payment posts a refund" do
    conn = razorpay
    with_http(200, '{"id":"rfnd_1","amount":500}') do
      obs = conn.provider_instance.invoke("refund_payment", { "payment_id" => "pay_1", "amount" => 500 })
      assert_equal "rfnd_1", obs["refund"]["id"]
    end
  end

  test "razorpay requires a payment_id and credentials" do
    assert_raises(Connectors::Error) { razorpay.provider_instance.invoke("fetch_payment", {}) }
    bare = Connector.create!(name: "No creds", provider: "razorpay")
    assert_raises(Connectors::Error) { bare.provider_instance.invoke("fetch_payment", { "payment_id" => "p" }) }
  end
end
