class AddLostReasonToDeals < ActiveRecord::Migration[8.1]
  def change
    add_column :deals, :lost_reason, :integer
  end
end
