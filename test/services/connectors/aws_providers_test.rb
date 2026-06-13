require "test_helper"

# Amazon SES + S3, both SigV4-signed via Connectors::AwsProvider. The signature
# itself is proven correct by aws_sigv4_test (get-vanilla vector); here we check
# the request shape: endpoint, body, and that a well-formed SigV4 Authorization +
# X-Amz-Date are attached (signature value varies with wall-clock time).
class Connectors::AwsProvidersTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body, headers = {}) = (@code = code; @body = body; @headers = headers)
    attr_reader :code, :body
    def [](k) = @headers[k]
  end
  class FakeHttp
    attr_reader :last
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @r)
  end
  def with_http(code, body = "{}", headers = {})
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body, headers)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def conn(provider, config:, creds: { "access_key_id" => "AKIDEXAMPLE", "secret_access_key" => "secret" })
    c = Connector.new(name: provider, provider: provider, config: config)
    c.credentials_hash = creds
    c
  end

  # --- SES ---

  test "ses send_email posts the SESv2 body with a ses-scoped SigV4 signature" do
    c = conn("amazon_ses", config: { "region" => "ap-south-1", "from_email" => "ops@acme.in" })
    with_http(200, %({"MessageId":"m-1"})) do |reqs|
      obs = c.provider_instance.invoke("send_email", { "to" => "a@b.com", "subject" => "Hi", "body" => "Hello" })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/v2/email/outbound-emails", req.path
      assert_match(/\AAWS4-HMAC-SHA256 Credential=AKIDEXAMPLE\/\d{8}\/ap-south-1\/ses\/aws4_request,/, req["Authorization"])
      assert_match(/\A\d{8}T\d{6}Z\z/, req["X-Amz-Date"])
      assert_equal "application/json", req["Content-Type"]
      sent = JSON.parse(req.body)
      assert_equal "ops@acme.in", sent["FromEmailAddress"]
      assert_equal [ "a@b.com" ], sent["Destination"]["ToAddresses"]
      assert_equal "Hello", sent["Content"]["Simple"]["Body"]["Text"]["Data"]
    end
  end

  test "ses send_email is confirm and requires to/subject/body" do
    assert_equal :confirm, Connectors::AmazonSesProvider.action("send_email").effective_decision_class
    c = conn("amazon_ses", config: { "region" => "ap-south-1", "from_email" => "ops@acme.in" })
    assert_raises(Connectors::Error) { c.provider_instance.invoke("send_email", { "subject" => "s", "body" => "b" }) }
  end

  # --- S3 ---

  test "s3 put_object PUTs the body with x-amz-content-sha256 signed, s3-scoped" do
    c = conn("amazon_s3", config: { "region" => "ap-south-1", "bucket" => "acme-files" })
    with_http(200, "", { "etag" => "\"abc123\"" }) do |reqs|
      obs = c.provider_instance.invoke("put_object", { "key" => "/reports/q3.txt", "content" => "hello" })
      assert obs["ok"]
      assert_equal "reports/q3.txt", obs["key"] # leading slash stripped
      req = reqs.last.last
      assert_kind_of Net::HTTP::Put, req
      assert_equal "/reports/q3.txt", req.path
      assert_equal "hello", req.body
      assert_equal Connectors::AwsSigv4.hashed_payload("hello"), req["x-amz-content-sha256"]
      assert_match(/\/s3\/aws4_request,/, req["Authorization"])
      assert_includes req["Authorization"], "x-amz-content-sha256"
    end
  end

  test "s3 put_object is confirm and requires key + content" do
    assert_equal :confirm, Connectors::AmazonS3Provider.action("put_object").effective_decision_class
    c = conn("amazon_s3", config: { "region" => "ap-south-1", "bucket" => "acme-files" })
    assert_raises(Connectors::Error) { c.provider_instance.invoke("put_object", { "key" => "k" }) }
  end

  test "aws providers require region + credentials" do
    no_region = conn("amazon_ses", config: { "from_email" => "x@y.com" })
    assert_raises(Connectors::Error) { no_region.provider_instance.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" }) }
    no_creds = conn("amazon_s3", config: { "region" => "ap-south-1", "bucket" => "b" }, creds: {})
    assert_raises(Connectors::Error) { no_creds.provider_instance.invoke("put_object", { "key" => "k", "content" => "c" }) }
  end
end
