# Inbound messaging (PG2): the provider's conversation key (WhatsApp wa_id /
# Telegram chat_id) so a reply threads onto its open case instead of opening a
# new one each time. Scoped per (tenant, connector) — the same chat id on two
# connectors is two conversations.
class AddSourceThreadIdToCases < ActiveRecord::Migration[8.1]
  def change
    add_column :cases, :source_thread_id, :string
    add_index :cases, [ :tenant_id, :source_connector_id, :source_thread_id ],
              name: "index_cases_on_tenant_connector_thread"
  end
end
