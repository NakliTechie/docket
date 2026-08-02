require "test_helper"

class Connectors::AuthorizationTest < ActiveSupport::TestCase
  test "may_invoke? tracks the connector:invoke permission for users" do
    # Functional roles
    assert Connectors::Authorization.may_invoke?(users(:super_admin))
    assert Connectors::Authorization.may_invoke?(users(:client_admin))
    assert Connectors::Authorization.may_invoke?(users(:customer_service))
    refute Connectors::Authorization.may_invoke?(users(:finance))
    refute Connectors::Authorization.may_invoke?(users(:sales))
    refute Connectors::Authorization.may_invoke?(users(:technical))
    refute Connectors::Authorization.may_invoke?(users(:readonly))
  end

  test "may_invoke? for a service account still checks the connectors:invoke scope" do
    assert Connectors::Authorization.may_invoke?(ServiceAccount.new(scopes: %w[connectors:invoke]))
    refute Connectors::Authorization.may_invoke?(ServiceAccount.new(scopes: %w[cases:read]))
  end

  test "service accounts require an action grant in addition to the coarse scope" do
    connector = Connector.create!(name: "Effector", provider: "http_json", target: "contacts",
                                  config: { "action_url" => "https://api.example.test/do" },
                                  field_mapping: { "external_id" => "id" },
                                  enabled_actions: %w[post_json])
    action = connector.provider_action("post_json")
    account = ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke])

    refute Connectors::Authorization.action_granted?(account, connector, action)
    account.grant_connector_actions!(connector, %w[post_json])
    assert Connectors::Authorization.action_granted?(account, connector, action)
  end
end
