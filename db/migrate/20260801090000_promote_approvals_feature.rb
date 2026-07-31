class PromoteApprovalsFeature < ActiveRecord::Migration[8.1]
  class MigrationTenant < ActiveRecord::Base
    self.table_name = "tenants"
  end

  def up
    MigrationTenant.find_each do |tenant|
      entitlements = tenant.entitlements.to_h
      next unless entitlements.key?("service_desk.approvals")

      entitlements.delete("service_desk.approvals")
      tenant.update_columns(entitlements: entitlements, updated_at: Time.current)
    end
  end

  def down
    MigrationTenant.find_each do |tenant|
      entitlements = tenant.entitlements.to_h
      next if entitlements.key?("service_desk.approvals")

      entitlements["service_desk.approvals"] = false unless entitlements.fetch("approvals", true)
      tenant.update_columns(entitlements: entitlements, updated_at: Time.current)
    end
  end
end
