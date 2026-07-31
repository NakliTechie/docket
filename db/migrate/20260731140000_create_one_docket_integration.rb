class CreateOneDocketIntegration < ActiveRecord::Migration[8.1]
  def change
    create_table :project_templates do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :key_prefix, null: false, default: "ONB"
      t.text :description
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :project_templates, %i[tenant_id name], unique: true

    create_table :project_template_items do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :project_template, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.text :description
      t.integer :kind, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.decimal :estimate, precision: 8, scale: 2
      t.integer :due_offset_days
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :project_template_items, %i[tenant_id project_template_id position],
              name: "index_project_template_items_order"

    add_reference :projects, :onboarding_deal, null: true,
                  foreign_key: { to_table: :deals, on_delete: :restrict }
    add_reference :projects, :project_template, null: true,
                  foreign_key: { on_delete: :nullify }
    add_index :projects, %i[tenant_id onboarding_deal_id], unique: true,
              where: "onboarding_deal_id IS NOT NULL",
              name: "index_projects_on_tenant_onboarding_deal"
  end
end
