# Per-connector budgeted autonomy: cap how many actions may flow through a
# single connector in a rolling window, regardless of which agent initiates
# them (the per-agent cap lives on ServiceAccount). nil = unlimited.
class AddActionBudgetToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :action_budget, :integer
    add_column :connectors, :action_budget_window_minutes, :integer
  end
end
