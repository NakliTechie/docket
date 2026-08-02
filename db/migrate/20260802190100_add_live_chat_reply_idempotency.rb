class AddLiveChatReplyIdempotency < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :source_message, foreign_key: { to_table: :messages }
    add_index :messages, [ :tenant_id, :source_message_id ], unique: true,
              where: "source_message_id IS NOT NULL",
              name: "index_messages_on_tenant_and_unique_source_message"
  end
end
