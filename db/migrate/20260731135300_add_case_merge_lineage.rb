class AddCaseMergeLineage < ActiveRecord::Migration[8.1]
  def change
    add_reference :cases, :merged_into, null: true,
                  foreign_key: { to_table: :cases, on_delete: :restrict }
    add_column :cases, :merged_at, :datetime
    add_index :cases, %i[tenant_id merged_into_id]
  end
end
