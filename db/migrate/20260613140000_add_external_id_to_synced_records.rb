# Sync-target plumbing: a dedup/provenance key (external_id) for synced
# Leads/Deals/Cases — the same role contacts.external_id already plays — plus
# source_connector_id on cases (contacts/leads/deals already have it) so every
# synced record type carries its provenance. Lets Connectors::Sync upsert
# non-contact targets idempotently.
class AddExternalIdToSyncedRecords < ActiveRecord::Migration[8.1]
  def change
    %i[leads deals cases].each do |table|
      add_column table, :external_id, :string
      add_index table, :external_id
    end
    add_column :cases, :source_connector_id, :integer
    add_index :cases, :source_connector_id
  end
end
