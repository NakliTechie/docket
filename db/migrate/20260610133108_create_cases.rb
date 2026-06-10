class CreateCases < ActiveRecord::Migration[8.1]
  def change
    create_table :cases do |t|
      t.string :subject, null: false
      t.text :description
      t.string :tracking_id, null: false
      t.integer :channel, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.references :category, foreign_key: true
      t.references :queue, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :contact, null: false, foreign_key: true
      t.references :sla_policy, foreign_key: true
      t.datetime :first_response_due_at
      t.datetime :resolution_due_at
      t.datetime :first_responded_at
      t.datetime :resolved_at
      t.datetime :closed_at
      t.datetime :reopened_at
      t.boolean :first_response_breached, null: false, default: false
      t.boolean :resolution_breached, null: false, default: false
      t.integer :reopen_count, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps

      t.index :tracking_id, unique: true
      t.index :status
      t.index :priority
      t.index [ :status, :queue_id ]
      t.index :created_at
      t.index :deleted_at
      t.index [ :first_response_breached, :first_response_due_at ]
      t.index [ :resolution_breached, :resolution_due_at ]
    end
  end
end
