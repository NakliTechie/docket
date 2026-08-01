class AddDeliveryClaimToCsatSurveys < ActiveRecord::Migration[8.1]
  def change
    add_column :csat_surveys, :delivery_enqueued_at, :datetime
  end
end
