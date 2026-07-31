class AddActionMacrosAndSignatures < ActiveRecord::Migration[8.1]
  def change
    add_column :macros, :message_kind, :string
    add_column :macros, :set_status, :string
    add_column :macros, :set_priority, :string
    add_reference :macros, :set_queue, foreign_key: { to_table: :queues, on_delete: :nullify }
    add_reference :macros, :set_assignee, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :users, :email_signature, :text
  end
end
