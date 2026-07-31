class PreventConcurrentConnectorRuns < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_connector_runs_on_one_running_per_connector"

  def up
    # Preserve the newest claim if old deployments already have overlaps, and
    # make the cleanup visible in run history instead of silently deleting it.
    execute <<~SQL.squish
      UPDATE connector_runs
      SET status = 2,
          finished_at = CURRENT_TIMESTAMP,
          error = COALESCE(error, 'superseded concurrent sync claim'),
          updated_at = CURRENT_TIMESTAMP
      WHERE status = 0
        AND id NOT IN (
          SELECT MAX(id)
          FROM connector_runs
          WHERE status = 0
          GROUP BY connector_id
        )
    SQL

    add_index :connector_runs, :connector_id, unique: true,
              where: "status = 0", name: INDEX_NAME
  end

  def down
    remove_index :connector_runs, name: INDEX_NAME
  end
end
