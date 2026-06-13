# Per-tenant settings: a key may exist once globally (tenant_id NULL, the
# deploy-wide default/fallback) AND once per tenant (the tenant's override).
# Two partial unique indexes replace the single global unique-on-key.
class ScopeSettingsByTenant < ActiveRecord::Migration[8.1]
  def up
    remove_index :settings, name: "index_settings_on_key"
    add_index :settings, :key, unique: true, where: "tenant_id IS NULL",
              name: "index_settings_on_key_global"
    add_index :settings, [ :tenant_id, :key ], unique: true, where: "tenant_id IS NOT NULL",
              name: "index_settings_on_tenant_id_and_key"
  end

  def down
    remove_index :settings, name: "index_settings_on_tenant_id_and_key"
    remove_index :settings, name: "index_settings_on_key_global"
    add_index :settings, :key, unique: true, name: "index_settings_on_key"
  end
end
