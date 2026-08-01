class CreateWorkRelationsAndAssignmentRules < ActiveRecord::Migration[8.1]
  def change
    create_table :work_item_relations do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :source, null: false, foreign_key: { to_table: :work_items, on_delete: :cascade }
      t.references :target, null: false, foreign_key: { to_table: :work_items, on_delete: :cascade }
      t.string :relation_type, null: false
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :work_item_relations, %i[tenant_id source_id target_id relation_type], unique: true,
              name: "index_work_relations_on_tenant_pair_and_type"
    add_check_constraint :work_item_relations, "source_id <> target_id",
                         name: "work_item_relations_distinct_items"

    create_table :work_assignment_rules do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :work_kind, null: false
      t.references :assignee, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.timestamps
    end
    add_index :work_assignment_rules, %i[tenant_id project_id work_kind], unique: true,
              name: "index_work_assignment_rules_on_project_and_kind"
  end
end
