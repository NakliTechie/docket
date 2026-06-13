# M3 (forward pass 2026-06-13): Dispatcher.persist upserts one Decision per
# (tenant, rule, subject) via find_or_initialize_by over a NON-unique index, so
# two concurrent runs could both insert and double-apply. Enforce uniqueness at
# the DB; persist now also rescues the race. Collapse any pre-existing dupes
# (keeping the earliest) before adding the index.
class UniqueDecisionPerTenantRuleSubject < ActiveRecord::Migration[8.1]
  def up
    if connection.adapter_name.match?(/postgresql/i)
      execute <<~SQL
        DELETE FROM decisions a USING decisions b
        WHERE a.id > b.id
          AND a.tenant_id = b.tenant_id AND a.rule = b.rule
          AND a.subject_type = b.subject_type AND a.subject_id = b.subject_id
      SQL
    end
    add_index :decisions, [ :tenant_id, :rule, :subject_type, :subject_id ],
              unique: true, name: "index_decisions_unique_per_tenant_rule_subject"
  end

  def down
    remove_index :decisions, name: "index_decisions_unique_per_tenant_rule_subject"
  end
end
