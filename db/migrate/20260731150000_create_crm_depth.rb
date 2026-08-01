class CreateCrmDepth < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    create_table :lead_capture_forms do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :slug, null: false
      t.column :field_mapping, json_type, null: false, default: {}
      t.text :consent_disclosure
      t.boolean :active, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.timestamps
    end
    add_index :lead_capture_forms, %i[tenant_id slug], unique: true
    add_index :lead_capture_forms, :tenant_id, unique: true, where: "is_default",
              name: "index_lead_capture_forms_one_default"

    add_column :leads, :provenance, json_type, null: false, default: {}
    add_column :leads, :consent_captured_at, :datetime
    add_column :leads, :consent_source, :string
    add_reference :leads, :merged_into, null: true,
                  foreign_key: { to_table: :leads, on_delete: :restrict }
    add_column :leads, :merged_at, :datetime
    add_index :leads, %i[tenant_id merged_into_id]

    create_table :products do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :sku, null: false
      t.text :description
      t.bigint :default_unit_price_cents
      t.string :currency, null: false, default: "INR"
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :products, %i[tenant_id sku], unique: true, where: "deleted_at IS NULL"

    create_table :deal_line_items do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :deal, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :restrict }
      t.string :description, null: false
      t.decimal :quantity, precision: 12, scale: 3, null: false, default: 1
      t.bigint :unit_price_cents, null: false
      t.string :currency, null: false
      t.timestamps
    end
    add_index :deal_line_items, %i[tenant_id deal_id product_id], unique: true

    create_table :competitors do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :website
      t.text :notes
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :competitors, %i[tenant_id name], unique: true, where: "deleted_at IS NULL"

    create_table :deal_competitors do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :deal, null: false, foreign_key: { on_delete: :cascade }
      t.references :competitor, null: false, foreign_key: { on_delete: :restrict }
      t.integer :disposition, null: false, default: 0
      t.text :notes
      t.timestamps
    end
    add_index :deal_competitors, %i[tenant_id deal_id competitor_id], unique: true
  end
end
