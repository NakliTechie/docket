class CreateCampaignAttribution < ActiveRecord::Migration[8.1]
  ATTRIBUTION_TABLES = %i[leads deals].freeze

  def change
    create_table :campaigns do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :channel, null: false, default: 5
      t.date :starts_on
      t.date :ends_on
      t.bigint :budget_cents, null: false, default: 0
      t.string :currency, null: false, default: "INR"
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :campaigns, %i[tenant_id code], unique: true,
              where: "deleted_at IS NULL", name: "index_live_campaigns_on_tenant_and_code"
    add_index :campaigns, %i[tenant_id utm_campaign], unique: true,
              where: "deleted_at IS NULL", name: "index_live_campaigns_on_tenant_and_utm"
    add_index :campaigns, :deleted_at
    add_check_constraint :campaigns, "budget_cents >= 0", name: "campaigns_budget_non_negative"
    add_check_constraint :campaigns, "ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on",
                         name: "campaigns_valid_date_window"

    add_reference :lead_capture_forms, :campaign, foreign_key: true

    ATTRIBUTION_TABLES.each do |table|
      add_reference table, :first_touch_campaign, foreign_key: { to_table: :campaigns }
      add_column table, :first_touch_at, :datetime
      add_column table, :first_touch_utm_source, :string
      add_column table, :first_touch_utm_medium, :string
      add_column table, :first_touch_utm_campaign, :string
      add_column table, :first_touch_utm_term, :string
      add_column table, :first_touch_utm_content, :string
      add_column table, :first_touch_landing_page, :text
      add_column table, :first_touch_referrer, :text
    end
  end
end
