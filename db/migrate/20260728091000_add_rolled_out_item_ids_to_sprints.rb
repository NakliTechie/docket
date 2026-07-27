class AddRolledOutItemIdsToSprints < ActiveRecord::Migration[8.1]
  # Which items were carried OUT of this sprint at close-out. Without it, the
  # velocity report counted only what remained, so every closed sprint showed
  # 100% of commitment delivered.
  def change
    add_column :sprints, :rolled_out_item_ids, :json, null: false, default: []
  end
end
