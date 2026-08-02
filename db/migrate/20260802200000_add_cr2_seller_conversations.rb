class AddCr2SellerConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :contacts, :job_title, :string
    add_column :contacts, :whatsapp_handle, :string
    add_column :contacts, :telegram_handle, :string

    add_column :leads, :job_title, :string
    add_column :leads, :whatsapp_handle, :string
    add_column :leads, :telegram_handle, :string

    add_column :deals, :notes, :text
    add_column :deals, :next_step, :text
    add_column :deals, :next_step_at, :datetime
    add_index :deals, %i[tenant_id next_step_at]

    create_table :crm_messages do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.references :author, polymorphic: true
      t.references :source_connector, foreign_key: { to_table: :connectors }
      t.integer :channel, null: false, default: 0
      t.integer :direction, null: false, default: 0
      t.integer :delivery_status, null: false, default: 0
      t.string :sender_email
      t.string :recipient_email
      t.string :subject_line
      t.text :body, null: false
      t.string :email_message_id
      t.string :external_message_id
      t.datetime :occurred_at, null: false
      t.datetime :delivery_claimed_at
      t.datetime :delivered_at
      t.text :delivery_last_error
      t.json :metadata, default: {}, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :crm_messages, %i[tenant_id subject_type subject_id occurred_at],
              name: "index_crm_messages_on_tenant_subject_occurred"
    add_index :crm_messages, :deleted_at
    add_index :crm_messages, %i[tenant_id email_message_id], unique: true,
              where: "email_message_id IS NOT NULL",
              name: "index_crm_messages_on_tenant_email_message"
    add_index :crm_messages, %i[tenant_id source_connector_id external_message_id], unique: true,
              where: "source_connector_id IS NOT NULL AND external_message_id IS NOT NULL",
              name: "index_crm_messages_on_tenant_connector_external"
  end
end
