class CreateEscalationRules < ActiveRecord::Migration[8.1]
  def change
    # PG3 — SLA-driven escalation matrix. Composes existing primitives (SLA
    # breach flags + elapsed-time-in-status + Notifications) into ordered tiers.
    # A rule matches open cases (by status/priority) and fires its levels in
    # order at increasing delays after a reference time (the breach moment or
    # status entry).
    create_table :escalation_rules do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.integer :trigger_type, null: false, default: 0
      t.string :breach_clock, null: false, default: "resolution"
      t.string :if_status
      t.string :if_priority
      t.timestamps
    end
    add_index :escalation_rules, %i[tenant_id position]

    # One tier: after +after_minutes+ past the rule's reference time, reassign
    # the case (then_assignee) and/or alert someone (notify_user).
    create_table :escalation_levels do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :escalation_rule, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0
      t.integer :after_minutes, null: false
      t.references :then_assignee, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :notify_user, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :escalation_levels, %i[tenant_id escalation_rule_id position]

    # Idempotency ledger (mirrors RoutingRuleExecution): a level fires once per
    # case per reference episode, so overlapping sweeps never double-escalate.
    create_table :escalation_executions do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :escalation_level, null: false, foreign_key: { on_delete: :cascade }
      t.references :case, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :reference_at, null: false
      t.datetime :executed_at, null: false
      t.timestamps
    end
    add_index :escalation_executions, %i[escalation_level_id case_id reference_at],
              unique: true, name: "index_escalation_executions_idempotency"
  end
end
