class CreateWorkLinks < ActiveRecord::Migration[8.1]
  # The seam that makes three modules one product: a work item can be linked to
  # a case, deal, lead or contact. Polymorphic on the OTHER side only — the work
  # item is always one end, so queries from either direction stay simple.
  def change
    create_table :work_links do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :work_item, null: false, foreign_key: true
      t.references :linkable, null: false, polymorphic: true
      t.integer :relation, null: false, default: 0 # escalated_from / related_to / onboarding_for
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :work_links, %i[work_item_id linkable_type linkable_id], unique: true,
              name: "index_work_links_uniqueness"
    add_index :work_links, %i[linkable_type linkable_id]
  end
end
