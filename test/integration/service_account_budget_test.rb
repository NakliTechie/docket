require "test_helper"

# The effector budget is settable through the existing service-account admin
# form (permit + field wiring), so an operator can bound an agent's blast
# radius without the console.
class ServiceAccountBudgetTest < ActionDispatch::IntegrationTest
  test "an admin sets an effector action budget on a service account" do
    sign_in_as users(:admin)
    sa = ServiceAccount.create!(name: "Triage agent", scopes: %w[connectors:invoke])

    patch admin_service_account_path(sa), params: { service_account: {
      name: "Triage agent", scopes: %w[connectors:invoke],
      action_budget: 25, action_budget_window_minutes: 30
    } }
    assert_response :redirect

    sa.reload
    assert_equal 25, sa.action_budget
    assert_equal 30, sa.action_budget_window_minutes
  end

  test "the new-account form renders the budget fields" do
    sign_in_as users(:admin)
    get new_admin_service_account_path
    assert_response :success
    assert_match "Effector budget", response.body
  end
end
