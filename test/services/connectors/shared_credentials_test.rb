require "test_helper"

# Step A: the shared app-level credential store + Connector#secret resolution.
class Connectors::SharedCredentialsTest < ActiveSupport::TestCase
  def shared(name: "api_setu", secrets: { "api_key" => "shared-key" })
    sc = SharedCredential.new(name: name, label: "API Setu")
    sc.secrets_hash = secrets
    sc.save!
    sc
  end

  # --- model ---

  test "secrets round-trip through the encrypted blob and are redacted from audit" do
    sc = shared(secrets: { "api_key" => "k1", "license_id" => "L-9" })
    assert_equal "k1", sc.reload.secret("api_key")
    assert_equal "L-9", sc.secret("license_id")
    entry = AuditEntry.where(auditable: sc).order(:id).last
    assert_not_includes entry.changeset.to_s, "k1"
  end

  test "name is a unique lowercase slug" do
    shared(name: "api_setu")
    dup = SharedCredential.new(name: "API_Setu", label: "x") # normalised to api_setu
    dup.secrets_hash = { "api_key" => "y" }
    assert_not dup.valid?
    assert SharedCredential.new(name: "bad slug!", label: "x").tap(&:valid?).errors[:name].any?
  end

  # --- resolution: own vault first, then shared ---

  test "a connector's own secret wins over the shared one" do
    sc = shared(secrets: { "api_key" => "shared" })
    conn = Connector.create!(name: "C", provider: "http_json", target: "contacts",
      field_mapping: { "external_id" => "id" },
      config: { "endpoint_url" => "https://api.example.com/c" }, shared_credential: sc)
    conn.credentials_hash = { "api_key" => "own" }
    conn.save!
    assert_equal "own", conn.secret("api_key")
  end

  test "a connector falls back to the shared credential when it has no own value" do
    sc = shared(secrets: { "api_key" => "shared" })
    conn = Connector.create!(name: "C", provider: "http_json", target: "contacts",
      field_mapping: { "external_id" => "id" },
      config: { "endpoint_url" => "https://api.example.com/c" }, shared_credential: sc)
    assert_equal "shared", conn.secret("api_key")
  end

  test "secret is nil when neither own nor shared has it" do
    conn = Connector.create!(name: "C", provider: "http_json", target: "contacts",
      field_mapping: { "external_id" => "id" }, config: {})
    assert_nil conn.secret("api_key")
  end

  # --- a provider reads through the shared credential ---

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
  def with_http(resp)
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(resp).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "Razorpay reads its key_id/key_secret from a shared credential — no own creds" do
    sc = shared(name: "rzp_account", secrets: { "key_id" => "rzp_1", "key_secret" => "shh" })
    conn = Connector.create!(name: "Refunds", provider: "razorpay", shared_credential: sc)
    with_http(FakeResponse.new("200", '{"id":"pay_1","status":"captured"}')) do |reqs|
      obs = conn.provider_instance.invoke("fetch_payment", { "payment_id" => "pay_1" })
      assert obs["ok"]
      assert_match(/\ABasic /, reqs.last.last["Authorization"])
    end
  end
end
