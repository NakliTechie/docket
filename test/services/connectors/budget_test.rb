require "test_helper"

# Budgeted autonomy: a per-agent cap on how many connector actions an agent
# may initiate within a rolling window — fail-safe deny when exhausted.
class Connectors::BudgetTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def connector
    Connector.create!(name: "Effector", provider: "http_json", target: "contacts",
      config: { "action_url" => "https://api.example.com/do" },
      field_mapping: { "external_id" => "id" }, enabled_actions: %w[post_json])
  end

  def agent(budget: nil, window: nil)
    ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke],
      action_budget: budget, action_budget_window_minutes: window)
  end

  # Parks as :proposed (write, not auto-approved) — no network needed.
  def propose(conn, principal, key: nil, behalf: "case:1")
    Connectors::Invoke.call(conn, "post_json", args: { "body" => { "x" => 1 } },
      principal: principal, on_behalf_of: behalf, idempotency_key: key)
  end

  test "an unbudgeted agent is unlimited" do
    conn = connector
    a = agent(budget: nil)
    5.times { propose(conn, a) }
    assert_equal 5, ConnectorInvocation.where(requested_by: a).count
  end

  test "a budget caps how many actions an agent may initiate, fail-safe deny" do
    conn = connector
    a = agent(budget: 2, window: 60)
    propose(conn, a)
    propose(conn, a)
    err = assert_raises(Connectors::Budget::Exceeded) { propose(conn, a) }
    assert_includes err.message, "2/2"
    # the denied action created no row
    assert_equal 2, ConnectorInvocation.where(requested_by: a).count
  end

  test "Budget::Exceeded is a Connectors::Error so callers can rescue uniformly" do
    assert_includes Connectors::Budget::Exceeded.ancestors, Connectors::Error
  end

  test "an idempotent retry does not consume budget" do
    conn = connector
    a = agent(budget: 1, window: 60)
    first = propose(conn, a, key: "k")
    again = nil
    assert_nothing_raised { again = propose(conn, a, key: "k") }
    assert_equal first.id, again.id
    assert_equal 1, ConnectorInvocation.where(requested_by: a).count
  end

  test "actions outside the rolling window no longer count" do
    conn = connector
    a = agent(budget: 1, window: 30)
    travel_to Time.current - 31.minutes do
      propose(conn, a)
    end
    # 31 min later the earlier action has aged out of the 30-min window
    assert_nothing_raised { propose(conn, a) }
    assert_equal 2, ConnectorInvocation.where(requested_by: a).count
  end

  test "a staff User principal carries no budget" do
    conn = connector
    user = User.create!(name: "Admin", email_address: "a-#{SecureRandom.hex(4)}@x.test",
                        password: "password123", role: :super_admin)
    10.times do
      Connectors::Invoke.call(conn, "post_json", args: { "body" => {} },
        principal: user, on_behalf_of: "case:1")
    end
    assert_equal 10, ConnectorInvocation.where(requested_by: user).count
  end

  test "a negative budget is rejected at the model" do
    assert_not ServiceAccount.new(name: "X", scopes: %w[connectors:invoke], action_budget: -1).valid?
  end
end
