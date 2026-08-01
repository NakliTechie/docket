class CreateSavedViews < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :saved_views do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :resource_type, null: false
      t.integer :context_id
      t.column :filters, json_type, null: false, default: {}
      t.timestamps
    end
    # Split the uniqueness boundary because SQL NULL values are distinct: a
    # single composite index would permit duplicate case views (context NULL)
    # under concurrent inserts.
    add_index :saved_views, %i[tenant_id user_id resource_type name], unique: true,
              where: "context_id IS NULL", name: "index_saved_case_views_on_owner_and_name"
    add_index :saved_views, %i[tenant_id user_id resource_type context_id name], unique: true,
              where: "context_id IS NOT NULL", name: "index_saved_work_views_on_owner_context_and_name"
  end
end
