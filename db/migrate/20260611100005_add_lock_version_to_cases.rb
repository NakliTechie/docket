# Optimistic locking on cases: two staff (or a staff edit racing a citizen
# reply) acting on the same case no longer silently clobber each other —
# the stale write raises ActiveRecord::StaleObjectError, surfaced as a
# "reload and retry" message (console) / 409 (API), and retried in jobs.
class AddLockVersionToCases < ActiveRecord::Migration[8.1]
  def change
    add_column :cases, :lock_version, :integer, default: 0, null: false
  end
end
