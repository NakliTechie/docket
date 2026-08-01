class AddLeadScoring < ActiveRecord::Migration[8.1]
  def change
    # PG5 — persist the computed lead score + band (previously compute-on-read).
    add_column :leads, :score, :integer, null: false, default: 0
    add_column :leads, :score_band, :integer, null: false, default: 0
    add_index :leads, %i[tenant_id score_band]

    # One editable scorecard per tenant (singleton): signal weights + band
    # thresholds + warm-source list. Defaults reproduce the old hard-coded rule.
    create_table :lead_scorecards do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :weight_email, null: false, default: 1
      t.integer :weight_phone, null: false, default: 1
      t.integer :weight_company, null: false, default: 1
      t.integer :weight_warm_source, null: false, default: 1
      t.integer :weight_owned, null: false, default: 1
      t.integer :warm_threshold, null: false, default: 3
      t.integer :hot_threshold, null: false, default: 5
      t.string :warm_sources, null: false, default: "referral,web_form"
      t.timestamps
    end
  end
end
