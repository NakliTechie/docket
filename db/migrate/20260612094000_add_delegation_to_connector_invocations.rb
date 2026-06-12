# Delegation binding (effector seam): a durable, opaque delegation_id minted
# per invocation and bound to the acting principal, propagated to downstream
# connector calls and stamped into the audit metadata — the non-repudiable
# thread that links an external side effect back to the agent that caused it
# (arXiv 2606.09692). `effect` snapshots the action's side-effect class at
# invocation time so the ledger stays self-describing if the provider later
# changes its action set.
class AddDelegationToConnectorInvocations < ActiveRecord::Migration[8.1]
  def change
    add_column :connector_invocations, :delegation_id, :string
    add_column :connector_invocations, :effect, :string
    add_index :connector_invocations, :delegation_id, unique: true
  end
end
