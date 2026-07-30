class CreateSequenceDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :sequence_deliveries do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :sequence_enrollment, null: false, foreign_key: true
      t.references :sequence_step, null: false, foreign_key: true
      t.references :connector, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :channel, null: false
      t.string :recipient
      t.json :payload, null: false, default: {}
      t.datetime :claimed_at
      t.datetime :delivered_at
      t.string :last_error
      t.timestamps
    end

    add_index :sequence_deliveries, %i[sequence_enrollment_id sequence_step_id],
              unique: true, name: "index_sequence_deliveries_on_enrollment_and_step"
    add_index :sequence_deliveries, %i[status created_at]
  end
end
