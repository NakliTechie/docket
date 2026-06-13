# Maker-checker approvals (PG4). An ApprovalProcess declares an entry criterion
# — a guarded case transition (e.g. closing a case) or an effector action that
# must be escalated to human review. An ApprovalRequest is the pending/approved/
# rejected record against a subject, carrying the approver's reasoned order.
class CreateApprovalProcesses < ActiveRecord::Migration[8.1]
  def change
    create_table :approval_processes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :trigger_type, null: false, default: 0
      t.string :trigger_key, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :approval_processes, [ :tenant_id, :trigger_type, :trigger_key ],
              unique: true, name: "index_approval_processes_on_tenant_and_trigger"

    create_table :approval_requests do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :approval_process, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :decided_by, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.string :requested_action
      t.text :reason
      t.datetime :decided_at
      t.timestamps
    end
    add_index :approval_requests, [ :tenant_id, :status ]
  end
end
