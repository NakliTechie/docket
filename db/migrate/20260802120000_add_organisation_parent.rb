class AddOrganisationParent < ActiveRecord::Migration[8.1]
  def change
    # PG9 — account hierarchy: an organisation may roll up under a parent
    # account (self-referential). Nullify on parent delete so a sub-account
    # survives its parent's removal as a root.
    add_reference :organisations, :parent, null: true,
                  foreign_key: { to_table: :organisations, on_delete: :nullify }
  end
end
