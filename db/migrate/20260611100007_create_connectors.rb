# Connector framework (Phase 0): a configured integration that pulls
# records from an external system into Docket on a schedule and/or on a
# webhook ping, with a per-run sync log. Credentials are encrypted at
# rest (ActiveRecord encryption). The provider abstraction (registry +
# field mapping + sync engine) is what every connector in the roadmap
# plugs into.
class CreateConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors do |t|
      t.string :name, null: false
      t.string :provider, null: false           # registry key, e.g. "http_json"
      t.string :target, null: false, default: "contacts" # Docket entity it feeds
      t.integer :status, null: false, default: 0 # active / paused / error
      t.json :config                             # provider-specific (endpoint, etc.)
      t.json :field_mapping                      # { docket_field => external_field }
      t.text :credentials                        # encrypted JSON blob of secrets
      t.string :webhook_secret                   # HMAC secret for the webhook ping
      t.integer :schedule_interval_minutes       # nil = manual / webhook-only
      t.datetime :last_synced_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :connectors, :deleted_at
    add_index :connectors, :status

    create_table :connector_runs do |t|
      t.references :connector, null: false, foreign_key: true
      t.integer :trigger, null: false, default: 0 # manual / scheduled / webhook
      t.integer :status, null: false, default: 0  # running / success / failed
      t.integer :records_in, default: 0, null: false
      t.integer :records_created, default: 0, null: false
      t.integer :records_updated, default: 0, null: false
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :connector_runs, [ :connector_id, :id ]
  end
end
