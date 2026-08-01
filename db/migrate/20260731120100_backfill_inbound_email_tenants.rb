class BackfillInboundEmailTenants < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE action_mailbox_inbound_emails
      SET tenant_id = (
        SELECT messages.tenant_id
        FROM messages
        WHERE messages.email_message_id = action_mailbox_inbound_emails.message_id
        LIMIT 1
      )
      WHERE tenant_id IS NULL
    SQL
  end

  def down
    # Tenant attribution is safe to retain if the schema migration is rolled back separately.
  end
end
