# Declarative case routing & assignment (the deterministic complement to the AI
# triage agent — a matching rule wins, AI is the fallback). A small ordered
# rules table: conditions (channel / priority / category / subject keyword, all
# "any" when blank) → actions (set queue / category / priority + an assignment
# strategy). Deliberately a rules table, not a visual flow builder.
class CreateRoutingRules < ActiveRecord::Migration[8.1]
  def change
    create_table :routing_rules do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0

      # Conditions (blank = "any"); a rule matches when ALL set conditions match.
      t.string :if_channel
      t.string :if_priority
      t.references :match_category, foreign_key: { to_table: :categories }
      t.string :if_subject_contains

      # Actions.
      t.references :then_queue, foreign_key: { to_table: :queues }
      t.references :then_category, foreign_key: { to_table: :categories }
      t.string :then_priority
      t.integer :then_assignment, null: false, default: 0 # keep / round_robin / least_loaded / specific_user
      t.references :then_assignee, foreign_key: { to_table: :users }

      t.timestamps
    end
    add_index :routing_rules, [ :tenant_id, :position ]

    # Provenance: which rule routed a case (nil = AI-routed or manual). Also the
    # signal that lets the AI agent skip re-classification.
    add_reference :cases, :routed_by_rule, foreign_key: { to_table: :routing_rules }
  end
end
