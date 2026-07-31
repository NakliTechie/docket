class EnforceOneActiveSprint < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_sprints_on_one_active_per_project"

  def up
    execute <<~SQL.squish
      UPDATE sprints
      SET status = 0, updated_at = CURRENT_TIMESTAMP
      WHERE status = 1 AND deleted_at IS NULL
        AND id NOT IN (
          SELECT MIN(id) FROM sprints
          WHERE status = 1 AND deleted_at IS NULL
          GROUP BY project_id
        )
    SQL
    add_index :sprints, :project_id, unique: true,
              where: "status = 1 AND deleted_at IS NULL", name: INDEX_NAME
  end

  def down
    remove_index :sprints, name: INDEX_NAME
  end
end
