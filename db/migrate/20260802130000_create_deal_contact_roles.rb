class CreateDealContactRoles < ActiveRecord::Migration[8.1]
  def change
    # PG8 — the role a contact plays on a deal (decision-maker / champion /
    # influencer / …). One role per contact per deal.
    create_table :deal_contact_roles do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :deal, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.integer :role, null: false, default: 0
      t.timestamps
    end
    add_index :deal_contact_roles, %i[tenant_id deal_id contact_id], unique: true
  end
end
