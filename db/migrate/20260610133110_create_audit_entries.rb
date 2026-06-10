class CreateAuditEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_entries do |t|
      t.references :actor, polymorphic: true
      t.string :action, null: false
      t.references :auditable, polymorphic: true, null: false
      t.json :changeset
      t.json :metadata
      t.string :previous_sha, limit: 64, null: false
      t.string :sha, limit: 64, null: false
      t.datetime :created_at, null: false

      t.index :sha, unique: true
      t.index :action
      t.index :created_at
    end
  end
end
