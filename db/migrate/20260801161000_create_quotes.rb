class CreateQuotes < ActiveRecord::Migration[8.1]
  def change
    # A quote derived from an issued Deliverable (Prithvi e2e, Phase 1).
    # Versioned: a revision is a new row sharing +number+ with version+1,
    # pointing at the one it +supersedes+. Tax/HSN-SAC live on the lines,
    # never on the deliverable.
    create_table :quotes do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :deal, null: false, foreign_key: { on_delete: :cascade }
      t.references :deliverable, null: true, foreign_key: { on_delete: :nullify }
      t.references :supersedes, null: true, foreign_key: { to_table: :quotes, on_delete: :nullify }
      t.integer :number, null: false
      t.integer :version, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.string :currency, null: false
      t.date :valid_until
      t.text :notes
      t.datetime :sent_at
      t.datetime :accepted_at
      t.datetime :rejected_at
      t.text :rejection_reason
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :quotes, %i[tenant_id number version], unique: true, where: "deleted_at IS NULL"
    add_index :quotes, %i[tenant_id deal_id]

    create_table :quote_line_items do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :quote, null: false, foreign_key: { on_delete: :cascade }
      t.string :description, null: false
      t.decimal :quantity, precision: 12, scale: 3, null: false, default: 1
      t.bigint :unit_price_cents, null: false, default: 0
      t.string :currency, null: false
      # Tax classification + rate are 100% greenfield here (never on DealLineItem).
      t.string :hsn_sac
      t.decimal :tax_rate, precision: 6, scale: 3, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :quote_line_items, %i[tenant_id quote_id]
  end
end
