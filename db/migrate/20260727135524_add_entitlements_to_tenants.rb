class AddEntitlementsToTenants < ActiveRecord::Migration[8.1]
  # Per-tenant feature overrides: { "work" => false }. Only DEVIATIONS from the
  # Features registry defaults are stored, so an existing tenant with `{}` keeps
  # today's behavior (everything enabled) — that is the zero-risk invariant this
  # column is designed around.
  def change
    add_column :tenants, :entitlements, :json, null: false, default: {}
  end
end
