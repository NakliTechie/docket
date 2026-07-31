class BindTenantExportsToInventory < ActiveRecord::Migration[8.0]
  def up
    add_column :tenant_export_receipts, :inventory_sha256, :string
    execute <<~SQL.squish
      UPDATE tenant_export_receipts
      SET inventory_sha256 = manifest_sha256
      WHERE inventory_sha256 IS NULL
    SQL
    change_column_null :tenant_export_receipts, :inventory_sha256, false
  end

  def down
    remove_column :tenant_export_receipts, :inventory_sha256
  end
end
