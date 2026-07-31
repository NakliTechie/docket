class CreateScheduledCaseRouting < ActiveRecord::Migration[8.1]
  def up
    add_column :routing_rules, :trigger_type, :string, null: false, default: "case_created" unless column_exists?(:routing_rules, :trigger_type)
    add_column :routing_rules, :after_minutes, :integer unless column_exists?(:routing_rules, :after_minutes)
    add_column :routing_rules, :if_status, :string unless column_exists?(:routing_rules, :if_status)
    unless column_exists?(:routing_rules, :use_business_hours)
      add_column :routing_rules, :use_business_hours, :boolean, null: false, default: true
    end

    unless column_exists?(:cases, :status_changed_at)
      add_column :cases, :status_changed_at, :datetime
      execute <<~SQL.squish
        UPDATE cases
        SET status_changed_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
        WHERE status_changed_at IS NULL
      SQL
      change_column_null :cases, :status_changed_at, false
    end
    add_index :cases, %i[status status_changed_at] unless index_exists?(:cases, %i[status status_changed_at])

    create_table :routing_rule_executions do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :routing_rule, null: true, foreign_key: { on_delete: :nullify }
      t.references :case, null: false, foreign_key: { on_delete: :cascade }
      t.string :rule_name, null: false
      t.datetime :case_status_changed_at, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :executed_at, null: false
      t.text :changes_summary
      t.timestamps
    end
    add_index :routing_rule_executions, %i[routing_rule_id case_id case_status_changed_at],
              unique: true, name: "index_routing_executions_on_rule_case_episode"
  end

  def down
    drop_table :routing_rule_executions
    remove_index :cases, %i[status status_changed_at]
    remove_column :cases, :status_changed_at
    remove_column :routing_rules, :use_business_hours
    remove_column :routing_rules, :if_status
    remove_column :routing_rules, :after_minutes
    remove_column :routing_rules, :trigger_type
  end
end
