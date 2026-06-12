require "test_helper"

# Slices 1+2: generic credential fields + effector-only providers, exercised
# through the first real named provider (Slack incoming webhook).
class Connectors::SlackWebhookProviderTest < ActiveSupport::TestCase
  WEBHOOK = "https://hooks.slack.com/services/T000/B000/xxxx".freeze

  def slack_connector(webhook: WEBHOOK)
    conn = Connector.create!(name: "Staff Slack", provider: "slack_webhook")
    if webhook
      conn.credentials_hash = { "webhook_url" => webhook }
      conn.save!
    end
    conn
  end

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
  def with_http(code, body = "ok")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  # --- credential field generalization (slice 1) ---

  test "a provider declares its secret fields; legacy auth :api_key still defaults to api_key" do
    assert_equal %w[webhook_url], Connectors::SlackWebhookProvider.descriptor.secret_fields
    assert_equal %w[api_key], Connectors::HttpJsonProvider.descriptor.secret_fields
  end

  # --- effector-only providers (slice 2) ---

  test "an effector-only connector saves with no field mapping" do
    conn = Connector.create!(name: "Staff Slack", provider: "slack_webhook")
    assert conn.persisted?
    assert_not conn.provider_syncs?
    assert Connector.new(provider: "http_json").provider_syncs? # http_json still syncs
  end

  test "slack_webhook is registered and declared effector-only" do
    assert Connectors::Registry.key?("slack_webhook")
    assert_not Connectors::SlackWebhookProvider.descriptor.syncs?
    assert_equal [], Connectors::SlackWebhookProvider.new(slack_connector(webhook: nil)).fetch
  end

  test "post_message is an autonomous action (mechanical, rights-neutral)" do
    action = Connectors::SlackWebhookProvider.action("post_message")
    assert_equal :autonomous, action.effective_decision_class
    assert_not action.requires_approval?
  end

  # --- the action itself (network stubbed) ---

  test "post_message posts the text to the webhook and returns an observation" do
    conn = slack_connector
    with_http(200) do |reqs|
      obs = conn.provider_instance.invoke("post_message", { "text" => "Case DKT-1 escalated" })
      assert obs["ok"]
      assert_equal "Case DKT-1 escalated", JSON.parse(reqs.last.last.body)["text"]
    end
  end

  test "post_message requires text" do
    assert_raises(Connectors::Error) { slack_connector.provider_instance.invoke("post_message", {}) }
  end

  test "post_message requires an https webhook and is SSRF-guarded" do
    http_conn = slack_connector(webhook: "http://hooks.slack.com/services/x")
    assert_raises(Connectors::Error) { http_conn.provider_instance.invoke("post_message", { "text" => "x" }) }

    ssrf = slack_connector(webhook: "https://169.254.169.254/x")
    err = assert_raises(Connectors::Error) { ssrf.provider_instance.invoke("post_message", { "text" => "x" }) }
    assert_includes err.message, "blocked"
  end

  test "the webhook secret round-trips through the encrypted vault" do
    conn = slack_connector
    assert_equal WEBHOOK, conn.reload.credentials_hash["webhook_url"]
  end
end
