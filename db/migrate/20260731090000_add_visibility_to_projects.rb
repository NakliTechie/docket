class AddVisibilityToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :visibility, :integer, null: false, default: 0
    add_index :projects, %i[tenant_id visibility]
    add_check_constraint :projects, "visibility IN (0, 1)", name: "projects_visibility_valid"
  end
end
