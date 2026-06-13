# Persisted decisioning: a Decision row per rule proposal (the history /
# contestability trail, hash-chain audited like the rest), plus a reversible
# `labels` array on the records a decision can act on — the segment tag an
# applied decision attaches.
class CreateDecisionsAndLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :decisions do |t|
      t.string :rule, null: false
      t.string :version, null: false
      t.string :subject_type, null: false
      t.integer :subject_id, null: false
      t.string :subject_label
      t.string :signal, null: false
      t.text :recommendation
      t.string :effect
      t.string :decision_class, null: false
      t.integer :status, null: false, default: 0
      t.text :reasoning
      t.integer :approved_by_id
      t.datetime :decided_at
      t.text :decision_reason
      t.timestamps
    end
    add_index :decisions, [ :subject_type, :subject_id ]
    add_index :decisions, [ :rule, :subject_type, :subject_id ]
    add_index :decisions, :status

    %i[leads deals cases].each { |table| add_column table, :labels, :json }
  end
end
