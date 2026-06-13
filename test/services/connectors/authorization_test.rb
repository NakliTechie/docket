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
end
