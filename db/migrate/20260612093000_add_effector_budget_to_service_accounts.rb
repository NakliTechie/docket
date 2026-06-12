# Budgeted autonomy (effector seam): a per-agent blast-radius limit. An
# AI agent (a ServiceAccount) may initiate at most `action_budget` connector
# actions within a rolling `action_budget_window_minutes`. Both nil = the
# pre-existing unlimited behaviour, so this is backward-compatible.
class AddEffectorBudgetToServiceAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :service_accounts, :action_budget, :integer
    add_column :service_accounts, :action_budget_window_minutes, :integer
  end
end
