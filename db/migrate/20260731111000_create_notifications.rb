class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :notifications do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :notifiable, polymorphic: true, null: false
      t.references :actor, polymorphic: true
      t.integer :kind, null: false
      t.integer :severity, null: false, default: 0
      t.string :dedupe_key, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.integer :occurrences, null: false, default: 1
      t.datetime :last_occurred_at, null: false
      t.datetime :read_at
      t.datetime :emailed_at
      t.integer :email_delivery_count, null: false, default: 0
      t.column :metadata, json_type
      t.timestamps
    end

    add_index :notifications, %i[tenant_id user_id dedupe_key], unique: true,
              name: "index_notifications_on_recipient_and_dedupe"
    add_index :notifications, %i[user_id read_at created_at],
              name: "index_notifications_on_user_inbox"
    add_check_constraint :notifications, "occurrences > 0",
                         name: "notifications_occurrences_positive"
    add_check_constraint :notifications, "email_delivery_count >= 0",
                         name: "notifications_email_delivery_count_nonnegative"
  end
end
