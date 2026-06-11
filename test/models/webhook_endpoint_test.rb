require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  test "rejects loopback / link-local / metadata / localhost URLs (M22 SSRF)" do
    [ "http://127.0.0.1/h", "http://localhost/h", "http://169.254.169.254/h",
      "http://[::1]/h", "http://0.0.0.0/h" ].each do |bad|
      endpoint = WebhookEndpoint.new(name: "x", url: bad, events: [ "case.created" ])
      assert_not endpoint.valid?, "#{bad} should be rejected"
      assert endpoint.errors[:url].any?
    end
  end

  test "allows public and private-network URLs (internal CRMs are fine)" do
    [ "https://crm.example.in/hook", "http://10.0.0.5/hook", "http://192.168.1.10/hook" ].each do |ok|
      endpoint = WebhookEndpoint.new(name: "x", url: ok, events: [ "case.created" ])
      assert endpoint.valid?, "#{ok} should be allowed: #{endpoint.errors.full_messages}"
    end
  end
end
