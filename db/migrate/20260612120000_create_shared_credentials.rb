# Shared app-level credentials/licenses: a named, encrypted secret bag reused
# across connectors (e.g. one API Setu key, a UIDAI licence). A connector
# optionally references one; its provider reads a secret from the connector's
# own vault first, then falls back to the shared credential. (No tenant
# dimension — single-tenant + per-connector + this shared pool.)
class CreateSharedCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :shared_credentials do |t|
      t.string :name, null: false          # stable id, e.g. "api_setu"
      t.string :label, null: false         # human label
      t.text :secrets                       # encrypted JSON blob { field => value }
      t.text :description
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :shared_credentials, :name, unique: true, where: "deleted_at IS NULL",
              name: "index_shared_credentials_on_name_live"
    add_index :shared_credentials, :deleted_at

    add_reference :connectors, :shared_credential, foreign_key: true, null: true
  end
end
