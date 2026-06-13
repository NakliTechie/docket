# Richer decisioning actions: a Decision can now carry an action beyond the
# default reversible "label" — e.g. route_case, enroll_lead — applied through
# the same decision_class gate. action_params holds the target (queue_id /
# sequence_id). Existing rows default to "label" (their current behaviour).
class AddActionToDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :decisions, :action, :string, null: false, default: "label"
    add_column :decisions, :action_params, :json
  end
end
