# Provenance: which connector ingested this record. Nullable — records created
# in-app (portal, manual, API) have no source connector. Unlocks "value per
# connector" reporting over synced contacts/leads/deals.
class AddSourceConnectorToRecords < ActiveRecord::Migration[8.1]
  def change
    %i[contacts leads deals].each do |table|
      add_column table, :source_connector_id, :integer
      add_index table, :source_connector_id
    end
  end
end
