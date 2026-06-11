# Lightweight, queryable security trail kept OUTSIDE the hash-chained
# AuditEntry (which requires a real auditable). Records authentication
# events with no associated user — primarily failed/throttled logins —
# so an operator can spot brute-force or credential-stuffing.
class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :security_events do |t|
      t.string :kind, null: false
      t.string :email
      t.string :ip_address
      t.string :user_agent
      t.json :metadata
      t.datetime :created_at, null: false
    end
    add_index :security_events, :created_at
    add_index :security_events, :kind
  end
end
