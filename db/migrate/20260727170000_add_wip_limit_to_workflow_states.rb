class AddWipLimitToWorkflowStates < ActiveRecord::Migration[8.1]
  # Soft WIP limit, KanZen's semantics: a column over its limit is flagged, not
  # blocked. A hard block teaches people to work around the board.
  def change
    add_column :workflow_states, :wip_limit, :integer
  end
end
