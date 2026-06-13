require "test_helper"

# Effector-only provider: WhatsApp Business Cloud API (Meta Graph API).
# Network is stubbed; we assert the wire shape (path, method, auth, body)
# rather than hitting Graph.
class Connectors::WhatsappCloudProviderTest < ActiveSupport::TestCase
  SEND_OK = '{"messaging_product":"whatsapp","contacts":[{"input":"15551234567","wa_id":"15551234567"}],"messages":[{"id":"wamid.ABC123"}]}'.freeze

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
    conn = Connector.new(provider: "http_json", name: "t", config: { "phone_number_id" => "109999888777" }.merge(config))
    conn.credentials_hash = { "access_token" => "EAAG-test-token" }.merge(creds)
    Connectors::WhatsappCloudProvider.new(conn)
  end

  # --- descriptor / decision class ---

  test "descriptor declares config + credential fields and is effector-only" do
    desc = Connectors::WhatsappCloudProvider.descriptor
    assert_equal "whatsapp_cloud", desc.key
    assert_equal "Communications", desc.category
    assert_equal %w[phone_number_id base_url], desc.config_fields
    assert_equal %w[access_token], desc.credential_fields
    assert_not desc.syncs?
  end

  test "effector-only provider inherits an empty fetch" do
    assert_equal [], provider.fetch
  end

  test "send_text_message is a confirm action (citizen-facing comms)" do
    action = Connectors::WhatsappCloudProvider.action("send_text_message")
    assert_equal :confirm, action.effective_decision_class
    assert action.requires_approval?
  end

  test "send_template_message is a confirm action" do
    assert_equal :confirm, Connectors::WhatsappCloudProvider.action("send_template_message").effective_decision_class
  end

  # --- send_text_message ---

  test "send_text_message posts a text message and returns the message id" do
    with_http(200, SEND_OK) do |reqs|
      obs = provider.invoke("send_text_message", { "to" => "15551234567", "text" => "Your case DKT-1 is updated" })
      assert obs["ok"]
      assert_equal "wamid.ABC123", obs["message_id"]

      req = reqs.last.last
      assert_kind_of Net::HTTP::Post, req
      assert_equal "/v21.0/109999888777/messages", req.path
      assert_equal "Bearer EAAG-test-token", req["Authorization"]

      body = JSON.parse(req.body)
      assert_equal "whatsapp", body["messaging_product"]
      assert_equal "individual", body["recipient_type"]
      assert_equal "15551234567", body["to"]
      assert_equal "text", body["type"]
      assert_equal "Your case DKT-1 is updated", body.dig("text", "body")
      assert_equal false, body.dig("text", "preview_url")
    end
  end

  test "send_text_message respects a configured base_url override" do
    prov = provider(config: { "base_url" => "https://graph.facebook.com/v19.0" })
    with_http(200, SEND_OK) do |reqs|
      prov.invoke("send_text_message", { "to" => "15551234567", "text" => "hi" })
      assert_equal "/v19.0/109999888777/messages", reqs.last.last.path
    end
  end

  test "send_text_message requires to and text" do
    with_http(200, SEND_OK) do
      assert_raises(Connectors::Error) { provider.invoke("send_text_message", { "text" => "hi" }) }
      assert_raises(Connectors::Error) { provider.invoke("send_text_message", { "to" => "15551234567" }) }
    end
  end

  test "send_text_message raises on a non-2xx response" do
    with_http(401, '{"error":{"message":"Invalid OAuth access token"}}') do
      assert_raises(Connectors::Error) { provider.invoke("send_text_message", { "to" => "15551234567", "text" => "hi" }) }
    end
  end

  # --- send_template_message ---

  test "send_template_message posts a template with the default language" do
    with_http(200, SEND_OK) do |reqs|
      obs = provider.invoke("send_template_message", { "to" => "15551234567", "template_name" => "appointment_reminder" })
      assert obs["ok"]
      assert_equal "wamid.ABC123", obs["message_id"]

      req = reqs.last.last
      assert_equal "/v21.0/109999888777/messages", req.path
      assert_equal "Bearer EAAG-test-token", req["Authorization"]

      body = JSON.parse(req.body)
      assert_equal "whatsapp", body["messaging_product"]
      assert_equal "template", body["type"]
      assert_equal "appointment_reminder", body.dig("template", "name")
      assert_equal "en_US", body.dig("template", "language", "code")
    end
  end

  test "send_template_message honours an explicit language code" do
    with_http(200, SEND_OK) do |reqs|
      provider.invoke("send_template_message",
                      { "to" => "15551234567", "template_name" => "welcome", "language" => "hi" })
      assert_equal "hi", JSON.parse(reqs.last.last.body).dig("template", "language", "code")
    end
  end

  test "send_template_message requires to and template_name" do
    with_http(200, SEND_OK) do
      assert_raises(Connectors::Error) { provider.invoke("send_template_message", { "to" => "15551234567" }) }
      assert_raises(Connectors::Error) { provider.invoke("send_template_message", { "template_name" => "x" }) }
    end
  end

  test "send_template_message raises on a non-2xx response" do
    with_http(400, '{"error":{"message":"Template name does not exist"}}') do
      assert_raises(Connectors::Error) do
        provider.invoke("send_template_message", { "to" => "15551234567", "template_name" => "nope" })
      end
    end
  end

  # --- missing config / auth ---

  test "a missing access_token raises" do
    prov = provider(creds: {})
    prov.connector.credentials_hash = {}
    with_http(200, SEND_OK) do
      assert_raises(Connectors::Error) { prov.invoke("send_text_message", { "to" => "1", "text" => "hi" }) }
    end
  end

  test "a missing phone_number_id raises" do
    prov = provider(config: { "phone_number_id" => "" })
    with_http(200, SEND_OK) do
      assert_raises(Connectors::Error) { prov.invoke("send_text_message", { "to" => "1", "text" => "hi" }) }
    end
  end

  test "an unknown action raises" do
    assert_raises(Connectors::Error) { provider.invoke("delete_account", {}) }
  end
end
