class CreateImportOperations < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :import_runs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :source, null: false
      t.string :source_instance, null: false, default: "default"
      t.string :status, null: false, default: "running"
      t.boolean :dry_run, null: false, default: true
      t.string :resume_token, null: false
      t.datetime :previous_watermark
      t.datetime :watermark
      t.column :checkpoint, json_type
      t.column :stats, json_type
      t.column :unmapped, json_type
      t.column :errors, json_type
      t.column :conflicts, json_type
      t.column :options, json_type
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :import_runs, :resume_token, unique: true
    add_index :import_runs, %i[tenant_id source source_instance status],
              name: "index_import_runs_for_resume"

    create_table :import_identities do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :source, null: false
      t.string :source_instance, null: false, default: "default"
      t.string :source_type, null: false
      t.string :external_id, null: false
      t.references :target, polymorphic: true
      t.references :last_seen_run, foreign_key: { to_table: :import_runs }
      t.datetime :source_updated_at
      t.string :source_digest, limit: 64
      t.column :imported_attributes, json_type
      t.column :metadata, json_type
      t.timestamps
    end
    add_index :import_identities,
              %i[tenant_id source source_instance source_type external_id],
              unique: true, name: "index_import_identities_on_source_identity"
    create_table :import_conflicts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :import_run, null: false, foreign_key: true
      t.references :import_identity, foreign_key: true
      t.string :source_type, null: false
      t.string :external_id, null: false
      t.references :target, polymorphic: true
      t.string :field, null: false
      t.column :previous_imported_value, json_type
      t.column :current_value, json_type
      t.column :incoming_value, json_type
      t.string :status, null: false, default: "unresolved"
      t.timestamps
    end
    add_index :import_conflicts, %i[tenant_id status]
  end
end
