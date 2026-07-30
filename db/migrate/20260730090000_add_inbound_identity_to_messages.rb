class AddInboundIdentityToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :source_connector, foreign_key: { to_table: :connectors }
    add_column :messages, :external_message_id, :string
    add_index :messages, %i[tenant_id source_connector_id external_message_id],
              unique: true,
              where: "source_connector_id IS NOT NULL AND external_message_id IS NOT NULL",
              name: "index_messages_on_tenant_connector_external_id"
  end
end
