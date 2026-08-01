class CreateTenantLifecycleAndPrivacy < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :tenant_export_receipts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :export_id, null: false
      t.string :manifest_sha256, null: false
      t.string :export_path, null: false
      t.column :row_counts, json_type, null: false, default: {}
      t.integer :attachment_count, null: false, default: 0
      t.datetime :completed_at, null: false
      t.timestamps
    end
    add_index :tenant_export_receipts, :export_id, unique: true
    add_check_constraint :tenant_export_receipts, "attachment_count >= 0",
                         name: "tenant_export_receipts_attachment_count_nonnegative"

    create_table :legal_holds do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.references :placed_by, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.datetime :expires_at
      t.datetime :released_at
      t.references :released_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :legal_holds, %i[tenant_id subject_type subject_id released_at],
              name: "index_legal_holds_on_active_subject"

    create_table :privacy_erasure_requests do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.references :requested_by, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.string :erasure_token, null: false
      t.column :summary, json_type, null: false, default: {}
      t.datetime :completed_at
      t.text :failure_reason
      t.timestamps
    end
    add_index :privacy_erasure_requests, :erasure_token, unique: true

    add_column :contacts, :erased_at, :datetime
    add_column :contacts, :erasure_token, :string
    add_index :contacts, %i[tenant_id erasure_token], unique: true,
              where: "erasure_token IS NOT NULL"

    add_column :audit_entries, :redacted_at, :datetime
    add_column :audit_entries, :redaction_event_id, :integer
    add_index :audit_entries, :redaction_event_id

    add_reference :action_mailbox_inbound_emails, :tenant, foreign_key: true
  end
end
