class CreateQuoteMilestones < ActiveRecord::Migration[8.1]
  def change
    # How the accepted quote bills: one invoice (fixed) or a milestone schedule.
    add_column :quotes, :billing_type, :integer, null: false, default: 0

    # A milestone on a milestone-billed quote (Prithvi e2e, D-3). Carries EITHER
    # an explicit amount or a percentage of the quote total; the schedule must
    # reconcile to the quote total.
    create_table :quote_milestones do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.bigint :amount_cents
      t.decimal :percentage, precision: 6, scale: 3
      t.date :due_on
      t.string :trigger
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :quote_milestones, %i[tenant_id quote_id]
  end
end
