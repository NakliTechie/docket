require "test_helper"

class Connectors::Msg91ProviderTest < ActiveSupport::TestCase
  def provider(secret: "WEBHOOKSECRET", creds: { "authkey" => "K" })
    conn = Connector.new(provider: "msg91", name: "m", config: {}, webhook_secret: secret)
    conn.credentials_hash = creds
    Connectors::Msg91Provider.new(conn)
  end

  def req(headers: {}, query: {})
    Struct.new(:headers, :query_parameters, keyword_init: true).new(headers: headers, query_parameters: query)
  end

  test "is an inbound (ingesting) provider" do
    assert Connectors::Msg91Provider.ingests?
  end

  test "accepts the shared token via header (preferred) or query; fail-closed otherwise" do
    assert provider.inbound_authentic?(req(headers: { "X-Webhook-Token" => "WEBHOOKSECRET" }))
    assert provider.inbound_authentic?(req(query: { "token" => "WEBHOOKSECRET" }))
    refute provider.inbound_authentic?(req(headers: { "X-Webhook-Token" => "nope" }))
    refute provider.inbound_authentic?(req), "missing token is rejected"
    refute provider(secret: "").inbound_authentic?(req(headers: { "X-Webhook-Token" => "" })), "unconfigured secret is rejected"
  end

  test "ingest normalizes across MSG91 field aliases; drops sender-less payloads" do
    msg = provider.ingest({ "sender" => "919876500000", "content" => "power cut", "message_id" => "M1" }).sole
    assert_equal "sms", msg[:channel]
    assert_equal "919876500000", msg[:sender][:external_id]
    assert_equal "power cut", msg[:body]
    assert_equal "M1", msg[:external_message_id]

    alt = provider.ingest({ "mobile" => "9199", "text" => "hi" }).sole
    assert_equal "9199", alt[:sender][:phone]
    assert_equal "hi", alt[:body]

    assert_empty provider.ingest({ "status" => "delivered" })
  end
end
