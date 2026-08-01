class CreateLeadRoutingRules < ActiveRecord::Migration[8.1]
  def change
    # Declarative lead-routing rules (PG1) — the lead-side mirror of RoutingRule.
    # Conditions on source/company/email-domain; the action assigns an owner by
    # strategy (round-robin / least-loaded / a specific user). Evaluated in
    # position order on lead creation; first active match wins.
    create_table :lead_routing_rules do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :if_source
      t.string :if_company_contains
      t.string :if_email_domain
      t.integer :then_assignment, null: false, default: 0
      t.references :then_owner, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :lead_routing_rules, %i[tenant_id position]
  end
end
