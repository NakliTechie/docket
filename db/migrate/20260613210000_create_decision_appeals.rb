# Customer appeal/contest trail for decisions of record (Decision#contestable?).
# An appeal is filed against an applied of_record decision; a reviewer either
# overturns it (the decision is reversed + dismissed) or denies it (it stands).
# Tenant-scoped + audited like the decision it contests.
class CreateDecisionAppeals < ActiveRecord::Migration[8.1]
  def change
    create_table :decision_appeals do |t|
      t.references :decision, null: false, foreign_key: true
      t.references :tenant, null: false, foreign_key: true
      t.references :appellant, foreign_key: { to_table: :contacts } # the contesting customer (optional)
      t.references :reviewed_by, foreign_key: { to_table: :users }  # the reviewer (set on resolution)
      t.text :grounds, null: false
      t.integer :status, null: false, default: 0 # pending / overturned / denied
      t.text :resolution
      t.datetime :resolved_at
      t.timestamps
    end
  end
end
