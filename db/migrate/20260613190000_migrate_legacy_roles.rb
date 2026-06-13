# RBAC legacy-role cutover. Reassign the remaining legacy rows to their
# functional successors (conservatively, toward least privilege) so the legacy
# enum values + matrix aliases can be removed. Raw SQL on the integer enum
# values to avoid coupling to the model (whose enum no longer defines them).
#
#   admin(0)      → super_admin(4)
#   supervisor(1) → client_admin(5)
#   agent(2)      → customer_service(8)
#   readonly(3)   → unchanged
#
# admin should be promoted to the right functional role by hand afterwards
# where customer_service is too narrow (finance/sales/technical).
class MigrateLegacyRoles < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE users SET role = 4 WHERE role = 0" # admin → super_admin
    execute "UPDATE users SET role = 5 WHERE role = 1" # supervisor → client_admin
    execute "UPDATE users SET role = 8 WHERE role = 2" # agent → customer_service
  end

  def down
    # Irreversible: the legacy enum values are removed in the same change set,
    # so there is nothing to roll back to.
    raise ActiveRecord::IrreversibleMigration
  end
end
