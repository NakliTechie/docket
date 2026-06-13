# Phase B of the tenancy seam: carry tenant_id on every owned table and make
# per-tenant uniqueness real. Existing deploys are single-tenant, so every row
# backfills to the primary tenant (seed runs AFTER migrate, so we ensure the
# row here). Children that are queried/swept directly (messages, enrollments,
# connector runs/invocations) get a denormalized tenant_id; purely transitive
# children (sla_targets, pipeline_stages, sequence_steps, queue_memberships,
# webhook_deliveries, api_tokens, oauth_access_tokens, sessions, active_storage)
# stay unscoped and reach their tenant through the parent.
class AddTenantToOwnedTables < ActiveRecord::Migration[8.1]
  ROOTS = %w[
    cases contacts leads deals users queues sla_policies categories connectors
    pipelines sequences macros reference_docs webhook_endpoints service_accounts
    organisations decisions
  ].freeze

  CHILDREN = %w[messages sequence_enrollments connector_runs connector_invocations].freeze

  SCOPED = (ROOTS + CHILDREN).freeze

  # Global unique indexes → tenant-scoped composites. Each entry:
  #   table, old_index_name, [columns], where-clause (nil = none)
  UNIQUE_INDEXES = [
    [ :cases, "index_cases_on_tracking_id", %i[tracking_id], nil ],
    [ :contacts, "index_contacts_on_external_id", %i[external_id], "external_id IS NOT NULL AND deleted_at IS NULL" ],
    [ :categories, "index_categories_on_name", %i[name], "deleted_at IS NULL" ],
    [ :macros, "index_macros_on_name", %i[name], "deleted_at IS NULL" ],
    [ :organisations, "index_organisations_on_name", %i[name], "deleted_at IS NULL" ],
    [ :pipelines, "index_pipelines_on_slug", %i[slug], "deleted_at IS NULL" ],
    [ :queues, "index_queues_on_name", %i[name], "deleted_at IS NULL" ],
    [ :queues, "index_queues_on_slug", %i[slug], "deleted_at IS NULL" ],
    [ :reference_docs, "index_reference_docs_on_title", %i[title], "deleted_at IS NULL" ],
    [ :sla_policies, "index_sla_policies_on_name", %i[name], "deleted_at IS NULL" ],
    [ :users, "index_users_on_email_address", %i[email_address], "deleted_at IS NULL" ]
    # service_accounts.client_id stays GLOBALLY unique (OAuth token endpoint
    # resolves it before tenant context exists).
  ].freeze

  def up
    primary_id = ensure_primary_tenant!

    SCOPED.each do |table|
      add_reference table, :tenant, null: true, index: true
      execute("UPDATE #{table} SET tenant_id = #{primary_id} WHERE tenant_id IS NULL")
      change_column_null table, :tenant_id, false
      add_foreign_key table, :tenants, column: :tenant_id
    end

    # Reads-only / fallback columns — nullable, no backfill, no FK-NOT-NULL.
    # audit_entries: filtered-read only (the chain stays global; NEVER scoped).
    # settings: NULL tenant_id = the deploy-wide/global value (tenant-first fallback).
    add_reference :audit_entries, :tenant, null: true, index: true
    add_reference :settings, :tenant, null: true, index: true

    UNIQUE_INDEXES.each do |table, old_name, columns, where|
      remove_index table, name: old_name
      add_index table, [ :tenant_id, *columns ], unique: true,
                name: "index_#{table}_on_tenant_id_and_#{columns.join('_and_')}", where: where
    end
  end

  def down
    UNIQUE_INDEXES.each do |table, old_name, columns, where|
      remove_index table, name: "index_#{table}_on_tenant_id_and_#{columns.join('_and_')}"
      add_index table, columns, unique: true, name: old_name, where: where
    end

    remove_reference :settings, :tenant
    remove_reference :audit_entries, :tenant
    SCOPED.each { |table| remove_reference table, :tenant, foreign_key: true }
  end

  private

  # The seed creates the primary tenant, but seeds run after migrate — ensure it
  # exists here so the backfill has a target. Raw SQL to avoid model coupling.
  def ensure_primary_tenant!
    id = select_value("SELECT id FROM tenants WHERE slug = 'primary'")
    return id if id

    execute(<<~SQL)
      INSERT INTO tenants (name, slug, status, created_at, updated_at)
      VALUES ('Docket', 'primary', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    select_value("SELECT id FROM tenants WHERE slug = 'primary'")
  end
end
