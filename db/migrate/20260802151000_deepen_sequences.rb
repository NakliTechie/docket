class DeepenSequences < ActiveRecord::Migration[8.1]
  def change
    add_reference :sequences, :owner, foreign_key: { to_table: :users }
    add_reference :sequences, :business_calendar, foreign_key: true

    add_column :sequence_steps, :delay_hours, :integer, null: false, default: 0
    add_column :sequence_steps, :use_business_hours, :boolean, null: false, default: false
    add_column :sequence_steps, :template_key, :string

    add_reference :sequence_deliveries, :activity, foreign_key: true
    add_column :sequence_deliveries, :tracking_token, :string
    add_column :sequence_deliveries, :opened_at, :datetime
    add_column :sequence_deliveries, :clicked_at, :datetime
    add_column :sequence_deliveries, :replied_at, :datetime
    add_column :sequence_deliveries, :open_count, :integer, null: false, default: 0
    add_column :sequence_deliveries, :click_count, :integer, null: false, default: 0
    reversible do |direction|
      direction.up do
        SequenceDelivery.reset_column_information
        ActsAsTenant.without_tenant do
          SequenceDelivery.where(tracking_token: nil).find_each do |delivery|
            delivery.update_columns(tracking_token: SecureRandom.hex(24))
          end
        end
      end
    end
    add_index :sequence_deliveries, :tracking_token, unique: true
  end
end
