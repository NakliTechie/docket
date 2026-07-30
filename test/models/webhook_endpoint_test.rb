require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  test "rejects loopback / link-local / metadata / localhost URLs (M22 SSRF)" do
    [ "http://127.0.0.1/h", "http://localhost/h", "http://169.254.169.254/h",
      "http://foo.localhost/h", "http://[::1]/h", "http://0.0.0.0/h",
      "http://10.0.0.5/h", "http://192.168.1.10/h" ].each do |bad|
      endpoint = WebhookEndpoint.new(name: "x", url: bad, events: [ "case.created" ])
      assert_not endpoint.valid?, "#{bad} should be rejected"
      assert endpoint.errors[:url].any?
    end
  end

  test "allows public URLs" do
    endpoint = WebhookEndpoint.new(name: "x", url: "https://crm.example.in/hook", events: [ "case.created" ])
    assert endpoint.valid?, endpoint.errors.full_messages
  end

  test "an operator can explicitly allowlist an internal CIDR" do
    original = ENV["DOCKET_OUTBOUND_ALLOW_CIDRS"]
    ENV["DOCKET_OUTBOUND_ALLOW_CIDRS"] = "10.20.0.0/16"
    allowed = WebhookEndpoint.new(name: "x", url: "http://10.20.1.5/hook", events: [ "case.created" ])
    denied = WebhookEndpoint.new(name: "x", url: "http://10.21.1.5/hook", events: [ "case.created" ])

    assert allowed.valid?, allowed.errors.full_messages
    refute denied.valid?
  ensure
    ENV["DOCKET_OUTBOUND_ALLOW_CIDRS"] = original
  end

  test "sanitized_url strips embedded credentials for display (L)" do
    endpoint = WebhookEndpoint.new(url: "https://user:s3cret@crm.example.in/hook")
    assert_equal "https://crm.example.in/hook", endpoint.sanitized_url
    refute_includes endpoint.sanitized_url, "s3cret"
  end
end
