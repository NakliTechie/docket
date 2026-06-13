# The apex of the tenancy seam. One row = one organisation. An ISOLATED deploy
# has exactly one tenant (the degenerate single-tenant case — scoping is then a
# constant predicate, so "your data, your DB, no other client's rows" stays
# literally true). A SHARED deploy has many, resolved by subdomain. The tenants
# table itself is never tenant-scoped (it's the apex) and never gets a default
# scope. See plan/rbac-research-2026-06-13.md.
class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :slug, null: false
      # NULL is allowed for the isolated singleton (no subdomain). Unique among
      # non-null values (Postgres + SQLite both treat NULLs as distinct).
      t.string :subdomain
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :tenants, :slug, unique: true
    add_index :tenants, :subdomain, unique: true
  end
end
