class CreateStorageDeletions < ActiveRecord::Migration[8.0]
  def change
    create_table :storage_deletions do |t|
      t.bigint :owner_tenant_id, null: false
      t.string :service_name, null: false
      t.string :blob_key, null: false
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :completed_at
      t.timestamps
    end

    add_index :storage_deletions, :blob_key, unique: true
    add_index :storage_deletions, %i[status created_at]
    add_index :storage_deletions, :owner_tenant_id
  end
end
