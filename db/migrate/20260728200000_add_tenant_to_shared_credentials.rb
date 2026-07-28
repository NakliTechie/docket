class AddTenantToSharedCredentials < ActiveRecord::Migration[8.1]
  # SharedCredential was the one top-level, directly-addressable, secret-bearing
  # model with no tenant_id — every other un-tenanted model is a child reached
  # through a tenanted parent. In shared mode that meant one paying customer
  # could list, read and destroy another's API keys, and the global name
  # uniqueness doubled as a cross-tenant existence oracle.
  def up
    add_reference :shared_credentials, :tenant, null: true, foreign_key: true

    # Existing rows predate tenancy on this table. An isolated deploy has exactly
    # one tenant and every row belongs to it; a shared deploy that already has
    # rows cannot have created them per-tenant, so the same assignment is the
    # only meaningful one available. Assign the oldest tenant and let the
    # operator re-home anything that needs moving.
    say_with_time "backfilling shared_credentials.tenant_id" do
      tenant_id = select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
      execute("UPDATE shared_credentials SET tenant_id = #{tenant_id.to_i}") if tenant_id
    end

    change_column_null :shared_credentials, :tenant_id, false

    # Name uniqueness has to be per-tenant now: globally unique names let one
    # tenant's chosen name collide with (and reveal) another's.
    remove_index :shared_credentials, name: "index_shared_credentials_on_name_live"
    add_index :shared_credentials, %i[tenant_id name],
              unique: true, where: "deleted_at IS NULL",
              name: "index_shared_credentials_on_tenant_id_and_name_live"
  end

  def down
    remove_index :shared_credentials, name: "index_shared_credentials_on_tenant_id_and_name_live"
    add_index :shared_credentials, :name,
              unique: true, where: "deleted_at IS NULL",
              name: "index_shared_credentials_on_name_live"
    remove_reference :shared_credentials, :tenant, foreign_key: true
  end
end
