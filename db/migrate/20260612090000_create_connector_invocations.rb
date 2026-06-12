# Connector framework (effector seam): a connector_invocation is one
# agent-initiated action through a connector — the outbound mirror of a
# connector_run's inbound sync. It records who asked (requested_by — an AI
# agent is a ServiceAccount), on whose behalf (a case/contact), the action +
# args, an approval gate for write/irreversible effects (approved_by is the
# human-of-record), and the structured result the agent reasons on. Like
# ConnectorRun it is append-in-spirit and audited (args/result redacted).
class CreateConnectorInvocations < ActiveRecord::Migration[8.1]
  def change
    create_table :connector_invocations do |t|
      t.references :connector, null: false, foreign_key: true
      t.string :action, null: false                 # provider action key
      t.integer :status, null: false, default: 0    # proposed/approved/rejected/executing/succeeded/failed
      t.json :args                                   # validated action arguments
      t.json :result                                 # structured observation returned to the agent
      t.text :error
      t.string :idempotency_key                      # exactly-once per connector
      t.string :on_behalf_of                         # the case/contact the agent acts for
      t.text :reasoning                              # the agent's stated rationale
      t.references :requested_by, polymorphic: true  # the agent (ServiceAccount) or a staff User
      t.references :approved_by, foreign_key: { to_table: :users } # human-of-record
      t.datetime :approved_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :connector_invocations, [ :connector_id, :id ]
    add_index :connector_invocations, [ :connector_id, :idempotency_key ],
              unique: true, name: "index_connector_invocations_idempotency"

    # Which provider actions this connector exposes to agents at all (deny by
    # default), and which write actions skip the human-of-record gate.
    add_column :connectors, :enabled_actions, :json
    add_column :connectors, :auto_approve_actions, :json
  end
end
