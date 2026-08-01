class AddDurableMailDeliveryState < ActiveRecord::Migration[8.0]
  def change
    add_column :csat_surveys, :delivery_status, :integer, null: false, default: 0
    add_column :csat_surveys, :delivery_attempts, :integer, null: false, default: 0
    add_column :csat_surveys, :delivery_claimed_at, :datetime
    add_column :csat_surveys, :delivery_last_error, :text
    add_index :csat_surveys, %i[tenant_id delivery_status]

    add_column :notifications, :email_status, :integer, null: false, default: 0
    add_column :notifications, :email_attempts, :integer, null: false, default: 0
    add_column :notifications, :email_claimed_at, :datetime
    add_column :notifications, :email_last_error, :text
    add_index :notifications, %i[tenant_id email_status]
  end
end
