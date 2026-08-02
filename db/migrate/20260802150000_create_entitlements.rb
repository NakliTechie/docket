class CreateEntitlements < ActiveRecord::Migration[8.1]
  def change
    create_table :entitlements do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :organisation, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :sla_policy, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_check_constraint :entitlements,
                         "((contact_id IS NOT NULL AND organisation_id IS NULL) OR " \
                         "(contact_id IS NULL AND organisation_id IS NOT NULL))",
                         name: "entitlements_exactly_one_holder"
    add_check_constraint :entitlements,
                         "ends_at IS NULL OR ends_at > starts_at",
                         name: "entitlements_valid_coverage_window"
    add_index :entitlements, %i[tenant_id name], unique: true,
              where: "deleted_at IS NULL", name: "index_live_entitlements_on_tenant_and_name"
    add_index :entitlements, %i[tenant_id contact_id starts_at],
              where: "deleted_at IS NULL", name: "index_live_entitlements_on_contact_coverage"
    add_index :entitlements, %i[tenant_id organisation_id starts_at],
              where: "deleted_at IS NULL", name: "index_live_entitlements_on_org_coverage"
    add_index :entitlements, :deleted_at
  end
end
