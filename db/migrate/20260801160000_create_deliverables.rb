class CreateDeliverables < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    # An engineering deliverable (Prithvi e2e, Phase 1) — the auditable basis a
    # quote derives from. Drafted on an engagement, approved by a distinct human
    # (maker-checker), issued frozen. Scope is engineering-only; price/tax live
    # on the Quote ("reports inform, never bill").
    create_table :deliverables do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :deal, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, null: true, foreign_key: { on_delete: :nullify }
      t.string :title, null: false
      t.text :summary
      t.integer :status, null: false, default: 0
      # Engineering scope only: [{description, quantity, unit, notes}]. No price,
      # no tax, no HSN/SAC. Frozen on issue; the quote turns each into a line.
      t.column :scope_items, json_type, null: false, default: []
      t.references :submitted_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :approved_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :approval_reason
      t.datetime :issued_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :deliverables, %i[tenant_id deal_id]
    add_index :deliverables, %i[tenant_id status]

    # A deliverable cites the study WorkItems it summarizes (one-way citation).
    create_table :deliverable_studies do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :deliverable, null: false, foreign_key: { on_delete: :cascade }
      t.references :work_item, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :deliverable_studies, %i[deliverable_id work_item_id], unique: true,
              name: "index_deliverable_studies_uniqueness"
  end
end
