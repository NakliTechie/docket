class CreateCustomFields < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :custom_field_definitions do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :resource_type, null: false
      t.string :key, null: false
      t.string :label, null: false
      t.string :field_type, null: false
      t.column :options, json_type, null: false, default: []
      t.boolean :required, null: false, default: false
      t.boolean :active, null: false, default: true
      t.boolean :reportable, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :custom_field_definitions, %i[tenant_id resource_type key], unique: true,
              name: "index_custom_fields_on_tenant_resource_key"
    add_index :custom_field_definitions, %i[tenant_id resource_type position],
              name: "index_custom_fields_on_tenant_resource_position"

    add_column :cases, :custom_fields, json_type, null: false, default: {}
    add_column :work_items, :custom_fields, json_type, null: false, default: {}
  end
end
