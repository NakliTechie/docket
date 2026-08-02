class AddDecisioningFeedback < ActiveRecord::Migration[8.1]
  def up
    add_column :contacts, :labels, json_type, null: false, default: []

    # The former admin-only UI avoided duplicate open appeals, but the domain
    # service did not enforce that invariant. Preserve the earliest pending
    # appeal if legacy callers raced, then make one-open-appeal structural.
    execute <<~SQL.squish
      UPDATE decision_appeals
      SET status = 2,
          resolution = COALESCE(resolution, 'Superseded by an earlier pending appeal'),
          resolved_at = COALESCE(resolved_at, CURRENT_TIMESTAMP),
          updated_at = CURRENT_TIMESTAMP
      WHERE status = 0
        AND id NOT IN (
          SELECT MIN(id)
          FROM decision_appeals
          WHERE status = 0
          GROUP BY tenant_id, decision_id
        )
    SQL
    add_index :decision_appeals, %i[tenant_id decision_id], unique: true,
              where: "status = 0", name: "idx_decision_appeals_one_pending"
  end

  def down
    remove_index :decision_appeals, name: "idx_decision_appeals_one_pending"
    remove_column :contacts, :labels
  end

  private

  def json_type
    connection.adapter_name.match?(/postgres/i) ? :jsonb : :json
  end
end
