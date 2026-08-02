require "test_helper"

class ServiceAccountConnectorGrantTest < ActiveSupport::TestCase
  def connector(name: "Effector")
    Connector.create!(name: name, provider: "http_json", target: "contacts",
                      config: { "action_url" => "https://api.example.test/do" },
                      field_mapping: { "external_id" => "id" },
                      enabled_actions: %w[post_json])
  end

  test "a new invoke-capable account starts with no connector authority" do
    account = ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke])
    conn = connector

    refute account.connector_action_granted?(conn, "post_json")
  end

  test "a grant is limited to one connector and selected actions" do
    account = ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke])
    granted = connector
    other = connector(name: "Other")
    account.grant_connector_actions!(granted, %w[post_json])

    assert account.connector_action_granted?(granted, "post_json")
    refute account.connector_action_granted?(granted, "ungranted_action")
    refute account.connector_action_granted?(other, "post_json")
  end

  test "removing the coarse scope revokes connector grants immediately" do
    account = ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke cases:read])
    account.grant_connector_actions!(connector, %w[post_json])

    assert_difference -> { ServiceAccountConnectorGrant.count }, -1 do
      account.update!(scopes: %w[cases:read])
    end
  end

  test "a grant rejects actions outside the connector exposure list" do
    account = ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke])
    grant = ServiceAccountConnectorGrant.new(tenant: account.tenant, service_account: account,
                                             connector: connector, actions: %w[delete_everything])

    assert_not grant.valid?
    assert grant.errors[:actions].any?
  end

  test "an account without the coarse scope cannot hold a connector grant" do
    account = ServiceAccount.create!(name: "Reader", scopes: %w[connectors:read])
    grant = ServiceAccountConnectorGrant.new(tenant: account.tenant, service_account: account,
                                             connector: connector, actions: %w[post_json])

    assert_not grant.valid?
    assert grant.errors[:service_account].any?
  end
end
