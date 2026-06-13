require "test_helper"

# Netcore Cloud — the per-channel Email / WhatsApp / SMS providers. Static
# credentials (HttpProvider), all sends :confirm. Wire contracts confirmed
# against Netcore's official api-summary: Email V6 = Bearer, WhatsApp =
# cpaaswa.netcorecloud.net/api/v2/message/nc, SMS = the Deflector array body.
class Connectors::NetcoreProvidersTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last
    def initialize(seq) = @seq = seq # a SHARED response queue across requests
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @seq.shift)
  end

  # Returns each response in `codes_bodies` ([code, body], …) on successive
  # requests across the whole stub block (each post_json builds a fresh
  # Net::HTTP, so the queue is shared by reference), capturing every request.
  def with_responses(*codes_bodies)
    captured = []
    seq = codes_bodies.map { |c, b| FakeResponse.new(c.to_s, b || "{}") }
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(seq).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  # Simpler single-response stub (one response per request).
  def with_http(code, body = "{}")
    with_responses([ code, body ]) { |captured| yield captured }
  end

  # --- Netcore Email ---

  def email_conn(config: {}, creds: {})
    c = Connector.create!(name: "Netcore Email", provider: "netcore_email",
      config: { "from_email" => "noreply@acme.in", "from_name" => "Acme" }.merge(config))
    c.credentials_hash = { "api_key" => "nk-secret" }.merge(creds)
    c.save!
    c
  end

  test "netcore_email send_email is confirm and posts the v6 personalizations body" do
    assert_equal :confirm, Connectors::NetcoreEmailProvider.action("send_email").effective_decision_class
    c = email_conn
    with_http(202, %({"data":{"message_id":"m1"},"status":"success"})) do |reqs|
      obs = c.provider_instance.invoke("send_email", { "to" => "a@b.com", "to_name" => "Ada", "subject" => "Hi", "body" => "<p>Hello</p>" })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/v6/mail/send", req.path
      assert_equal "Bearer nk-secret", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "a@b.com", sent["personalizations"][0]["to"][0]["email"]
      assert_equal "Ada", sent["personalizations"][0]["to"][0]["name"]
      assert_equal "noreply@acme.in", sent["from"]["email"]
      assert_equal "html", sent["content"][0]["type"]
    end
  end

  test "netcore_email requires to/subject/body and a from_email" do
    p = email_conn.provider_instance
    assert_raises(Connectors::Error) { p.invoke("send_email", { "subject" => "s", "body" => "b" }) }
    no_from = email_conn(config: { "from_email" => "" }).provider_instance
    with_http(202) { assert_raises(Connectors::Error) { no_from.invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" }) } }
  end

  # --- Netcore WhatsApp ---

  def wa_conn
    c = Connector.create!(name: "Netcore WA", provider: "netcore_whatsapp", config: { "source_id" => "src-1" })
    c.credentials_hash = { "auth_key" => "wa-key" }
    c.save!
    c
  end

  test "netcore_whatsapp template send posts the message array with locale + attributes" do
    c = wa_conn
    with_http(200, %({"status":"success","data":{"id":"uuid-1"}})) do |reqs|
      obs = c.provider_instance.invoke("send_whatsapp",
        { "to" => "919869566055", "template_name" => "order_update", "variables" => [ "Ada", "5" ], "language" => "en" })
      assert_equal "uuid-1", obs["id"]
      req = reqs.last.last
      assert_equal "/api/v2/message/nc", req.path
      assert_equal "Bearer wa-key", req["Authorization"]
      msg = JSON.parse(req.body)["message"][0]
      assert_equal "919869566055", msg["recipient_whatsapp"]
      assert_equal "template", msg["message_type"]
      assert_equal "src-1", msg["source"]
      assert_equal "order_update", msg["type_template"][0]["name"]
      assert_equal [ "Ada", "5" ], msg["type_template"][0]["attributes"]
      assert_equal "en", msg["type_template"][0]["language"]["locale"]
    end
  end

  test "netcore_whatsapp text send uses message_type text and requires to + text" do
    c = wa_conn
    with_http(200, %({"status":"success","data":{"id":"uuid-2"}})) do |reqs|
      c.provider_instance.invoke("send_whatsapp_text", { "to" => "919869566055", "text" => "Thanks!" })
      msg = JSON.parse(reqs.last.last.body)["message"][0]
      assert_equal "text", msg["message_type"]
      assert_equal "Thanks!", msg["type_text"][0]["content"]
    end
    assert_raises(Connectors::Error) { c.provider_instance.invoke("send_whatsapp_text", { "to" => "919869566055" }) }
    assert_raises(Connectors::Error) { c.provider_instance.invoke("send_whatsapp", { "to" => "919869566055" }) }
  end

  # --- Netcore SMS ---

  def sms_conn
    c = Connector.create!(name: "Netcore SMS", provider: "netcore_sms",
      config: { "sender_id" => "ACMEIN", "dlt_template_id" => "T123", "feed_id" => "F1" })
    c.credentials_hash = { "api_key" => "sms-key" }
    c.save!
    c
  end

  test "netcore_sms send_sms is confirm and posts the deflector body with an api-key header" do
    assert_equal :confirm, Connectors::NetcoreSmsProvider.action("send_sms").effective_decision_class
    c = sms_conn
    with_http(200, %({"status":"success"})) do |reqs|
      obs = c.provider_instance.invoke("send_sms", { "mobile" => "919900000001", "text" => "Your OTP is 123" })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/messages/send", req.path
      assert_equal "sms-key", req["api-key"]
      sent = JSON.parse(req.body)
      assert_kind_of Array, sent # Deflector wants a JSON array of message objects
      assert_equal "919900000001", sent[0]["to"][0]["phoneNumber"]
      assert_equal "ACMEIN", sent[0]["sms"]["From"]
      assert_equal "Your OTP is 123", sent[0]["sms"]["Text"]
      assert_equal "SMS", sent[0]["flow"][0]["channel"]
    end
  end

  test "netcore_sms requires a mobile and text" do
    p = sms_conn.provider_instance
    assert_raises(Connectors::Error) { p.invoke("send_sms", { "text" => "Hi" }) }
    assert_raises(Connectors::Error) { p.invoke("send_sms", { "mobile" => "919900000001" }) }
  end

  # --- catalogue ---

  test "the three netcore providers are registered, static-credential, effector-only comms" do
    %w[netcore_email netcore_whatsapp netcore_sms].each do |key|
      desc = Connectors::Registry.descriptor(key)
      assert_equal key, desc.key
      assert_equal "Communications", desc.category
      assert_not desc.syncs?
      assert_not Connectors::Registry.klass(key) < Connectors::OauthProvider
    end
  end
end
