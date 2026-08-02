class CreateRealtimeIntake < ActiveRecord::Migration[8.1]
  def change
    create_table :live_chats do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :case, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :ended_at
      t.timestamps
    end
    add_index :live_chats, [ :tenant_id, :case_id ], unique: true
    add_index :live_chats, [ :tenant_id, :token_digest ], unique: true
    add_index :live_chats, [ :tenant_id, :expires_at ]

    create_table :call_records do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :case, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :connector, null: false, foreign_key: true
      t.string :provider_call_id, null: false
      t.string :from_number, null: false
      t.string :to_number
      t.string :status, null: false, default: "received"
      t.string :recording_url
      t.integer :duration_seconds
      t.json :ivr_answers, null: false, default: {}
      t.text :transcript
      t.json :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end
    add_index :call_records, [ :tenant_id, :connector_id, :provider_call_id ],
              unique: true, name: "index_call_records_on_tenant_connector_provider_id"
    add_check_constraint :call_records, "duration_seconds IS NULL OR duration_seconds >= 0",
                         name: "call_records_duration_nonnegative"
  end
end
