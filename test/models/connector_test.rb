require "test_helper"

class ConnectorTest < ActiveSupport::TestCase
  def build_connector(**overrides)
    Connector.new({
      name: "CRM pull", provider: "http_json", target: "contacts",
      config: { "endpoint_url" => "https://api.example.com/contacts" },
      field_mapping: { "external_id" => "id", "email" => "email", "name" => "name" }
    }.merge(overrides))
  end

  test "valid with a known provider and an identity in the mapping" do
    assert build_connector.valid?
  end

  test "rejects an unknown provider" do
    c = build_connector(provider: "nope")
    assert_not c.valid?
    assert c.errors[:provider].any?
  end

  test "mapping must reach an identity (external_id or email)" do
    c = build_connector(field_mapping: { "name" => "name", "phone" => "phone" })
    assert_not c.valid?
    assert c.errors[:field_mapping].any?
  end

  test "enabled_actions must be actions the provider exposes" do
    assert build_connector(enabled_actions: %w[post_json]).valid?, "post_json is a real http_json action"
    c = build_connector(enabled_actions: %w[post_json nonsense])
    assert_not c.valid?
    assert c.errors[:enabled_actions].any?
  end

  test "auto_approve_actions must be a subset of enabled_actions" do
    c = build_connector(enabled_actions: %w[post_json], auto_approve_actions: %w[other])
    assert_not c.valid?
    assert c.errors[:auto_approve_actions].any?
  end

  test "a negative per-connector action budget is rejected" do
    assert_not build_connector(action_budget: -1).valid?
  end

  test "credentials are encrypted at rest" do
    c = build_connector
    c.credentials_hash = { "api_key" => "topsecret-xyz" }
    c.save!
    stored = Connector.connection.select_value("SELECT credentials FROM connectors WHERE id = #{c.id}")
    refute_includes stored.to_s, "topsecret-xyz", "credentials must not be stored in cleartext"
    assert_equal "topsecret-xyz", c.reload.credentials_hash["api_key"]
  end

  test "credentials and webhook_secret are redacted from the audit log" do
    c = build_connector
    c.credentials_hash = { "api_key" => "s3cr3t" }
    c.save!
    entry = AuditEntry.where(auditable: c, action: "connector.create").last
    assert entry, "create should be audited"
    refute_includes entry.changeset.to_json, "s3cr3t"
    refute_includes entry.changeset.to_json, c.webhook_secret
  end

  test "a webhook secret is minted on create" do
    c = build_connector
    c.save!
    assert c.webhook_secret.to_s.start_with?("whk_")
  end

  test "due? respects the schedule interval and last_synced_at" do
    c = build_connector(schedule_interval_minutes: 60)
    c.save!
    assert c.due?, "never-synced active connector is due"
    c.update!(last_synced_at: 10.minutes.ago)
    assert_not c.due?, "synced within the interval is not due"
    c.update!(last_synced_at: 2.hours.ago)
    assert c.due?, "synced beyond the interval is due"
    c.update!(status: :paused)
    assert_not c.due?, "paused connector is never due"
  end

  test "manual/webhook-only connectors (no interval) are never scheduler-due" do
    c = build_connector(schedule_interval_minutes: nil)
    c.save!
    assert_not c.due?
  end
end
