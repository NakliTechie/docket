class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    # PG2 — the Activity/Task/Event object. A logged interaction or a planned
    # task hung off any CRM/desk record (polymorphic subject: Contact / Lead /
    # Deal / Case). Feeds the Customer-360 timeline and the rep task queue.
    create_table :activities do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :subject, polymorphic: true, null: false
      t.references :owner, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :kind, null: false, default: 0
      t.string :title, null: false
      t.text :body
      t.datetime :due_at
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :activities, %i[tenant_id subject_type subject_id]
    add_index :activities, %i[tenant_id owner_id status due_at]
  end
end
